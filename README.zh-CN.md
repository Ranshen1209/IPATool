# IPATool

<p align="center">
  <img src="IPATool/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" alt="IPATool App Icon" width="160" height="160">
</p>

[English README](README.md)

一个使用 SwiftUI 构建的原生 macOS 工具，将 Apple 账号登录、应用版本检索、许可证请求、分块下载、校验以及 IPA 元数据重写整合进一个桌面工作台。

## 功能概览

- Apple ID 登录与会话恢复  
  登录流程通过私有 Apple 服务协议适配层发起。登录成功后，账号凭证、验证码和会话信息会保存到 Keychain，并尽可能恢复 Cookie 与登录状态。
- 应用版本检索  
  输入数字形式的 App ID 后可以拉取版本列表；也可以直接指定 Version ID 来查询某个特定构建。
- 许可证请求  
  对选中的版本发起购买/许可证状态请求，并区分 `licensed`、`already owned`、`failed` 等状态。
- 下载任务工作台  
  在许可证请求成功后创建下载任务，支持暂停、取消、重试、删除，并可在 Finder 中定位输出目录与缓存目录。
- 分块下载与断点恢复  
  下载器会先解析远端文件大小，再按照配置切分 chunk，支持并发下载、任务持久化以及应用重启后的恢复。
- IPA 校验与重写  
  下载完成后可执行 MD5 校验，并向 IPA 中写入 `iTunesMetadata.plist` 与 `SC_Info/*.sinf` 签名数据。
- 日志与风险中心  
  内置结构化日志查看器，以及单独的风险页面，用来明确哪些链路较稳定，哪些仍然依赖私有 Apple 协议。
- 面向沙箱的目录授权  
  输出目录与缓存目录通过 security-scoped bookmark 持久化，更适配签名后的 macOS 沙箱环境。

## 当前 UI 结构

应用通过侧边栏划分为以下几个工作区：

- `Account`  
  登录、登出、查看当前 Apple 账号会话，并处理二次验证提示。
- `Search`  
  输入 App ID / Version ID，加载可用版本，对选中的版本请求许可证并创建下载任务。
- `Tasks`  
  查看任务进度、状态、重试次数、输出路径与缓存路径。
- `Logs`  
  查看登录、检索、购买、下载、IPA 重写等流程日志，并按级别过滤。
- `Risks`  
  直接展示项目内置的运行风险说明。
- `Settings`  
  配置输出目录、缓存目录、chunk 并发数、chunk 大小，并支持清理缓存。

## 代码中实际实现的流程

典型工作流如下：

1. 在 `Account` 页面输入 Apple ID 与密码。
2. 登录成功后，应用会把账户凭证和会话状态写入 Keychain。
3. 在 `Search` 页面输入数字形式的 App ID，并可选输入 Version ID。
4. 应用通过 catalog repository 拉取版本数据；如果私有 catalog 没返回可用版本，普通搜索会尝试回退到公开的 iTunes Lookup 元数据。
5. 选择某个版本并发起许可证请求。
6. 许可证请求成功后，如果当前版本对象缺少可下载 URL 或签名数据，应用会再次请求一个“可下载版本”。
7. 创建下载任务后，chunk downloader 会把任务写入 `tasks.json`，并并发拉取各个分块。
8. 所有 chunk 合并完成后，应用会把 IPA 移到目标输出目录，执行可选 MD5 校验，然后重写 metadata 与 `sinf`。
9. 最终结果会显示在 `Tasks` 页面，详细过程可以在 `Logs` 页面查看。

## 项目结构

```text
IPATool/
├── App/              # AppContainer、AppModel、路由、Command 菜单
├── Data/             # DTO、协议适配网关、Repository
├── Domain/           # 领域模型、协议、UseCase
├── Infrastructure/   # HTTP、Keychain、下载器、日志、存储、IPA 重写
├── Presentation/     # SwiftUI 页面
└── Assets.xcassets/  # 应用资源与图标
```

- `App/AppContainer.swift`  
  负责依赖注入，将 settings、keychain、HTTP client、repositories、use cases 和 downloader 组装起来。
- `App/AppModel.swift`  
  负责整个应用状态的编排，是 UI 与 use case 之间的主协调层。
- `Data/Gateways/AppleServicesProtocolAdapters.swift`  
  封装登录、catalog、purchase 三条 Apple 协议请求。
- `Data/Repositories/*`  
  把 DTO / 协议层转换为面向业务的 `AuthServicing`、`AppCatalogServicing`、`PurchaseServicing`、`DownloadServicing` 和 `IPAProcessingServicing`。
- `Infrastructure/Download/ChunkedDownloadManager.swift`  
  是项目的核心实现之一，负责 chunk 规划、HTTP Range 下载、持久化、恢复、合并、重试以及状态更新。
- `Infrastructure/Archive/IPAArchiveRewriter.swift`  
  通过系统命令解包、写入 metadata / sinf，并重新打包 IPA。
- `Presentation/*`  
  当前的 SwiftUI 桌面界面。

## 关键实现

### 1. 登录与 Keychain

- `AppleAuthRepository` 会在登录成功后保存以下信息：
  - Apple ID / 密码
  - 可复用的验证码
  - `AppSession`
  - 当前 Apple 相关 Cookie
- 启动时，`AppModel.bootstrap()` 会尝试：
  - 恢复沙箱目录访问权限
  - 读取已持久化的下载任务
  - 恢复缓存的 Apple ID
  - 从 Keychain 恢复 session 与 cookies

### 2. 双重验证处理

- 初次登录时会先尝试正常认证。
- 如果 Apple 明确要求验证，`AppModel` 会弹出 `VerificationCodeSheet`。
- 如果许可证请求过程中出现 `Purchase Session Expired`，应用会优先尝试用缓存验证码恢复会话；失败后再提示输入新的验证码。

### 3. 搜索与版本解析

- `AppleCatalogRepository` 会解析私有 catalog 返回的 song 列表。
- `StoreDTOMapper` 会从 metadata 中推导候选 `externalVersionID`。
- 普通搜索在必要时可以回退到公开 `itunes.apple.com/lookup`，但这一回退只提供基础元数据，不保证包含可下载 URL 或签名信息。

### 4. 分块下载

下载器会执行以下工作：

- 使用 `HEAD` 或 `Range: bytes=0-0` 推断远端文件大小。
- 根据设置中的 chunk size 生成 chunk 计划。
- 并发下载多个 chunk。
- 严格校验：
  - HTTP 状态码必须是 `206`
  - `Content-Range` 必须匹配
  - chunk 长度必须符合预期
- 将任务和版本上下文持久化到 `tasks.json`，支持冷启动恢复。

### 5. IPA 处理

`IPAProcessingRepository` 会：

- 在存在 MD5 时执行校验。
- 组装 metadata 字典并写入 `iTunesMetadata.plist`。
- 解码 base64 `sinf` 数据，并写入 `SC_Info` 下的对应位置。
- 使用 `IPAArchiveRewriter` 调用 `/usr/bin/ditto` 和 `/usr/bin/zip` 重新打包 IPA。

## 配置与本地数据

应用当前会将本地状态存放在以下位置：

- Keychain  
  保存账号凭证与恢复的会话。
- `~/Library/Application Support/IPATool/settings.json`  
  保存输出目录、缓存目录、chunk 并发数和 chunk 大小。
- `~/Library/Application Support/IPATool/bookmarks.plist`  
  保存目录访问所需的 security-scoped bookmark。
- 默认缓存目录  
  `~/Library/Caches/IPATool`
- 默认输出目录  
  `~/Downloads`

## 环境要求

- macOS
- Xcode 26.4 或兼容版本
- SwiftUI / Observation
- 允许访问网络

项目当前已启用以下 entitlement：

- `com.apple.security.network.client`

## 运行方式

### 使用 Xcode

1. 使用 Xcode 打开 [IPATool.xcodeproj](/Volumes/APFS_HD/Documents/Xcode/IPATool/IPATool.xcodeproj)
2. 选择 `IPATool` scheme
3. 直接运行 macOS 应用

### 首次使用建议

1. 打开 `Settings`
2. 确认输出目录和缓存目录
3. 重新通过目录选择器授权一次目录访问
4. 在 `Account` 中登录
5. 到 `Search` 中测试一个 App ID

## 测试覆盖

仓库当前包含一组单元测试，重点覆盖以下行为：

- 登录 use case 中的日志写入
- Apple 登录网关对 plist 响应的映射
- `AppModel` 在登出前会暂停需要认证的下载任务
- 并发验证码请求的互斥保护
- 清理缓存时保留 `tasks.json`
- 下载任务状态恢复语义
- 冷启动恢复下载任务时恢复持久化版本上下文
- HTTP Range 响应无效时的失败保护

测试目录位于 [IPAToolTests](/Volumes/APFS_HD/Documents/Xcode/IPATool/IPAToolTests)。

## 风险与边界

这部分非常重要，因为代码中已经明确把这些内容标记为风险项：

- Apple 登录、catalog lookup 和 purchase/license 请求依赖私有或未公开的 Apple 服务协议。
- 这些协议可能随时失效，也可能带来账号风控、法律或合规问题。
- IPA metadata / `sinf` 重写属于明显的策略敏感能力，不适合作为面向公众的 App Store 功能。
- 该项目目前更适合：
  - 内部研究
  - 开发者实验
  - 私有分发环境
- 不适合直接宣称为：
  - 稳定的生产工具
  - 面向公众的 Mac App Store 产品

## 致谢

[IPATool.js](https://github.com/wf021325/ipatool.js)  
[Codex](https://github.com/openai/codex)
