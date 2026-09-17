# 12 · 跨订阅节点聚合（把多个机场合并成一个优选池）

> 目标：让「线路冗余」不依赖单一机场。把多个订阅合并为一个池子，任一机场故障或抽风时，池内其它节点自动顶上，而不是整条线路一起挂。
> 适用：Clash Verge Rev（Mihomo 内核），已有 `docs/02` 的规则分流框架。

## 一、为什么需要这一层

`docs/02` 的 `线路冗余` 组是 `[自建 VPS, AI智能优选, CF备用]`。这解决了「线路类型」的冗余（自建 / 机场 / CF 三种不同故障域），但没有解决**同一层内部的冗余**：

- 只用一个机场 → 该机场跑路、被墙、或节点集体抽风时，这一层就只剩自建和 CF
- 手工维护「机场里哪几个节点好」→ 每次订阅刷新都要人工过一遍，不可持续

跨订阅聚合解决的是：**把订阅当作会变化的输入源，用 provider 机制自动装卸，池子始终是「当前所有可用节点的并集」。**

## 二、核心机制：`proxy-providers`

Mihomo 的 `proxy-providers` 允许把外部订阅声明为一个**节点集合**，再由策略组通过 `use:` 引用。与直接把节点写进 `proxies:` 的区别：

| 方式 | 订阅刷新后 | 维护成本 |
|---|---|---|
| 节点写死在 `proxies:` | 变旧、失效，需手工替换 | 高 |
| `proxy-providers` + 组内 `use:` | 自动跟随订阅更新 | 低 |

一个 provider 只描述「去哪拿节点」，不描述「怎么用」；「怎么用」在策略组里用 `use:` 声明。

## 三、配置结构

### 3.1 声明 providers

每个订阅一个 provider，`path` 必须唯一（否则互相覆盖缓存）：

```yaml
proxy-providers:
  prov-a:
    type: http
    url: "<SUBSCRIPTION_URL_A>"
    path: ./providers/prov-a.yaml
    interval: 3600
    health-check:
      enable: true
      url: http://www.gstatic.com/generate_204
      interval: 300
      lazy: false
    exclude-filter: "<信息型节点过滤正则>"

  prov-b:
    type: http
    url: "<SUBSCRIPTION_URL_B>"
    path: ./providers/prov-b.yaml
    interval: 3600
    health-check:
      enable: true
      url: http://www.gstatic.com/generate_204
      interval: 300
      lazy: false
    exclude-filter: "<信息型节点过滤正则>"
```

### 3.2 过滤「信息型假节点」

多数机场订阅会在节点列表里**混入非节点条目**（用节点名字段承载公告），常见形态：

- 流量播报类：剩余流量、到期时间、距离下次重置
- 客服/公告类：官网、防失联、套餐到期、教程、请去使用

这些条目没有真实服务端，一旦被策略组当节点使用就是**必然失败的成员**。用 `exclude-filter` 在 provider 层剔除：

```yaml
exclude-filter: "(?i)(剩余流量|距离下次重置|套餐到期|防失联|官网|请去使用|教程|过期时间|重置)"
```

要点：

- 正则是**黑名单**语义，命中即排除；机场文案会变，建议每次接入新订阅后复查一次
- 在 **provider 层**过滤优于在组层过滤 —— 假节点不会进入任何引用该 provider 的组
- 过滤后应核对「provider 实际节点数 < 订阅条目数」，差值应约等于公告条目数

### 3.3 聚合组（`use:` 引用多 provider）

```yaml
proxy-groups:
  - name: 全订阅优选
    type: url-test
    use:
      - prov-a
      - prov-b
    url: http://www.gstatic.com/generate_204
    interval: 300
    tolerance: 50
    lazy: false
```

`url-test` 会在**所有成员的并集**中选延迟最低者；任一订阅里的节点都可能被选中。

参数取舍：

| 参数 | 作用 | 权衡 |
|---|---|---|
| `interval` | 重测周期 | 越小越灵敏，但重测流量/开销越大 |
| `tolerance` | 切换阈值（ms） | 太小 → 两个节点来回跳车；太大 → 不跟随更快的节点 |
| `lazy` | `true` 时仅在需要时测 | 省资源，但候选集更新滞后 |

## 四、持久化：不要手改生成文件

Clash Verge 会在**订阅刷新时重新生成 `clash-verge.yaml`**。任何直接写进生成文件的改动都会被覆盖。

正确做法是写入订阅的**覆盖层**（`%APPDATA%\io.github.clash-verge-rev...\profiles\`）：

| 文件 | 作用 | 关键点 |
|---|---|---|
| `<profile>.proxies` | `append` 自定义节点 | 增加单节点 |
| `<profile>.groups` | `append` 自定义策略组 | 增加组 |
| `<profile>.rules` | `prepend` / `append` / `delete` | 改规则 |
| merge 文件（如 `mXXXXX.yaml`） | 合并整段配置 | DNS、`proxy-providers` 这类「非节点非组」段落放这里 |

⚠️ **两种覆盖文件的包装格式不同，混用会静默失效**：

- `proxies` / `groups` / `rules` 覆盖层使用 `prepend` / `append` / `delete` 三段式：

```yaml
append:
  - name: <组名>
    type: url-test
    use: [prov-a, prov-b]
```
- merge 文件用于**整段合并**，直接写键值（如 `dns:`、`proxy-providers:`），**不要再套 `append:`**

判据：如果一个段落天然是「列表里加几项」（节点、组、规则），用三段式覆盖层；如果是「覆盖一整块对象」（DNS、providers），用 merge 文件。

## 五、校验与重载

改完**先校验，再重载**——配置写错会导致内核起不来，直接断网。

```powershell
# 1) 语法/结构校验（用完整生成配置，不是片段）
& "D:\Clash Verge\verge-mihomo.exe" -t -d "<VERGE_DATA_DIR>" -f "<VERGE_DATA_DIR>\clash-verge.yaml"
#    期望末行: configuration file ... test is successful

# 2) 重载（Clash Verge 默认关闭 TCP controller，走命名管道）
#    PUT /configs  body={"path":"<clash-verge.yaml 绝对路径>"}
#    期望 HTTP 204

# 3) 确认 provider 都加载成功
#    GET /providers/proxies  → 应能看到每个 prov-*
```

命名管道的通用调用方式见 `docs/02`。

## 六、验证聚合是否真的生效

**不要只看「配置加载成功」**——要确认组里的成员确实来自多个订阅：

```powershell
# 1) 组的成员清单与当前选中项
#    GET /proxies/<URL编码的组名>
#    → "all" 数组 = 实际成员（应显著大于单个订阅的节点数）
#    → "now"   = 当前选中项（必须是真实节点，不能是公告条目）

# 2) 假节点残留检查
#    对 "all" 数组用第三步的正则做一次反查，期望命中数为 0

# 3) 端到端：真实流量穿过该组
curl.exe -4 -x http://127.0.0.1:7897 https://api.ipify.org
```

## 七、架构选择：默认 vs 速度优先

`docs/02` 的默认 `线路冗余` 顺序是 **自建 VPS → 聚合池 → CF**，理由是自建线路可控、行为确定。

聚合池引入后，另一种可选顺序是 **聚合池 → 自建 VPS → CF**：

| 顺序 | 优点 | 代价 |
|---|---|---|
| 自建 → 池 → CF（默认） | 出口确定、便于排障；自建是你自己的机器 | 峰值速度受限于自建带宽 |
| 池 → 自建 → CF | 峰值速度取全网最优 | 出口 IP 与跳数不确定；池内节点质量随订阅波动 |

**这是取舍，不是升级**。如果 DNS 依赖该组（本仓库 DNS 用 `#线路冗余` 做 DoH），顺序变化会同步影响 DNS 稳定性——把 DNS 托付给「每 300s 可能换一次出口」的 url-test 组，抖动会比固定线路明显。改顺序前先想清楚这一点。

**住宅出口（`MIYA-STATIC`）与本节无关，必须保持独立且 Fail Closed**（见 `docs/03`）：住宅组只放住宅节点，绝不与机房池互相回退。

## 八、常见误判

| 观察到的现象 | 不能直接得出的结论 | 还缺什么 |
|---|---|---|
| 短时间内若干次请求全部成功 | 「该线路很稳定」 | 样本太小；线路质量需要跨时段长样本，短测只能证明「此刻通」 |
| 代理返回 HTTP 502 | 「供应商故障」 | 502 只说明链路某处返回了错误，无法区分供应商侧 / 本地 / 中间链路；需换时段、换出口复现 |
| 域名解析成功（fake-ip） | 「DNS 链路健康」 | fake-ip 是本地合成应答，不代表上游 DoH 真正可达 |
| 延迟很低 | 「速度很快」 | 延迟 ≠ 吞吐，必须单独测吞吐（见下） |
| 测试期间偶发超时 | 「聚合方案坏了」 | 重测/切换窗口本身就会造成抖动，需与基线对照 |

**延迟与吞吐必须分开测**：

```powershell
# 延迟：组测速
# GET /proxies/<组名>/delay?timeout=5000&url=http://www.gstatic.com/generate_204

# 吞吐：实际下载固定字节数，看速度而非时间
curl.exe -4 -x http://127.0.0.1:7897 -o NUL -w "%{speed_download}" "https://speed.cloudflare.com/__down?bytes=8000000"
```

「延迟通过 ≠ 吞吐正常」——机场超售时延迟很好看，实际下载很慢。

## 九、接入新订阅的检查清单

1. 先在**隔离环境**验证新订阅的协议是否被内核支持（较新的 `anytls` 等），确认无误再动主配置——直接改主配置而内核不支持会导致**整个配置加载失败**，是一次全量断网
2. 新增一个 provider（唯一 `path`）+ 加进 `exclude-filter` 过滤
3. 把新 provider 加进聚合组的 `use:` 列表
4. `-t` 校验 → 重载 → 核对 `/providers/proxies`
5. 核对组成员数增量与假节点残留
6. 端到端验证出口 IP 与吞吐
7. 观察一个订阅刷新周期，确认改动没被生成流程覆盖

## 十、局限

- 聚合提升的是**可用性**，不改变「每个成员节点的真实质量」
- 池子越大，单次全量重测的开销越大；`interval` 与 `lazy` 需要按机器性能取舍
- 所有订阅仍可能来自同一上游机房 → **故障域未必真正独立**；真正的独立性来自 `docs/06` 的自建 VPS 与 `docs/02` 的 CF 线路
- provider 的 `url` 含订阅凭据，属敏感信息，**入库一律用占位符**
