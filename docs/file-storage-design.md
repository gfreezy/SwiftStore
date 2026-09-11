# 独立的 iCloud 文件存储组件

状态：首版随 4.1.0 提供。更新于 2026-09-11。实现与接入说明见 [SwiftFileStore](../SwiftFileStore/README.md)。业务始终访问 App 自己的本地目录，组件负责与 iCloud 容器交换文件，系统负责网络传输。本文替代之前的“迁移后只保留容器文件”方案。

## 1. 边界与存储

提供独立 Swift Package / 模块 SwiftFileStore，最低支持 iOS 16。实现使用 Foundation，必要时使用 CryptoKit 流式校验，不依赖 SwiftStore、SQLite、业务 Entity、changeLog 或 CloudKit 同步引擎，不提供自定义同步 Backend。

调用方只保存 FileReference（作用域及稳定相对路径），文件与业务记录的关联、引用更新和业务清理任务由调用方负责。

```text
明确保存 → App 本地文件 → 复制到 iCloud 容器 → 系统上传
业务读取 ← App 本地文件 ← 自动下载、复制更新 ← iCloud
```

本地文件始终位于 Application Support 中组件管理的目录，不因同步迁移到别处。iCloud 容器只是系统同步所需的位置；它的 URL 不返回给业务方。本机可能同时有本地文件和容器副本，接受这项空间成本以换取本地可用性。导出快照、系统临时文件及冲突版本可能增加空间占用，不承诺严格只有两份。

## 2. 配置、路径与身份

```swift
let files = try await SwiftFileStore(
    rootPath: "Reed",             // 默认 ""
    iCloudEnabled: true,          // 默认 true
    containerIdentifier: "iCloud.com.example.app" // 默认 nil
)

let file = try await files.importFile(
    from: sourceURL,
    path: "books/book-123.pdf"
)
```

路径规则为“默认文件目录 / rootPath / path”。rootPath 是相对根路径，默认空；path 包含完整文件名及可选多级目录，省略时生成 UUID 名称并保留源扩展名。显式空 path、绝对路径、越界及符号链接逃逸均拒绝。目录按需创建，不重复拼接 rootPath。

示意布局：

```text
Application Support/SwiftFileStore/<scope>/
  Files/<rootPath>/<path>       # 对业务提供 URL 的本地内容
  State/                       # 账号、文件来源、待办、恢复记录
  Staging/                     # 未提交的复制内容
  Deferred/                    # 使用结束后才安装的更新等临时内容

iCloud ubiquity container/
  Attachments/<rootPath>/<path>
```

存储作用域与容器配置匹配，锁和账号绑定独立，不能因嵌套 rootPath 导致实例同时扫描或修改对方内容。管理目录不进入文件列表和云端同步。

首版采用不可变附件：一个唯一 path 对应一份内容，不提供同路径覆盖或重命名。替换附件时新建路径、切换业务引用、删除旧文件。自定义路径也不得复用已删除名称。同路径相同内容可幂等处理，不同内容报告冲突。组件不承诺本地查重等于跨设备全局唯一。

## 3. 保存、上传和必要记录

保存先将文件复制到本地 staging，保留调用方源文件；内容与明确保存意图通过可恢复提交协议提交。成功返回表示本地保存完成且上传意图不会因重启丢失，不表示文件已上传。提交前取消/失败不破坏已有文件；提交后取消不撤销已成功的保存。

组件在原账号可用时将明确保存的文件复制到 iCloud 容器，执行协调访问及目标校验。目标为占位文件时先等待下载，不能以本机缺内容认定远端不存在；相同字节幂等处理，不同内容或版本冲突保留并报告。

区分 pending（尚未放入容器）、handedOff（已放入容器）和 uploaded（系统报告上传完成）。已经交给系统的文件不反复复制催促上传。只要没有明确删除或显式释放操作，本地原件持续保留，上传后也不自动清理。

由于本地目录现在同时包含“本机创建文件”和“远端下载副本”，不能再扫描目录就把所有文件当作待上传。需要以本机 JSON 持久化系统无法还原的信息：

- 明确新增/删除的意图和必要恢复阶段。
- 文件来源、内容校验与已接收版本的线索，用于区分下载副本、处理重启恢复及远端消失。
- 账号绑定、已知远端删除及尚待物理清理的状态。

不维护业务 changeLog，不向云端同步这些记录，不需要 isInICloud 业务字段。文件位置固定；系统上传/下载状态仍从 metadata / resource values 查询，缓存值不能代替重新核验。

isUbiquitousItem 只能检查容器文件是否被指定用于 iCloud。App 本地副本不是 ubiquitous 文件，无法通过这个接口判断它是否需要上传。[Apple API](https://developer.apple.com/documentation/foundation/filemanager/isubiquitousitem(at:))

如果复制成功但状态提交前崩溃，恢复时核对目标、账号与内容。无法区分从未交付与交付后远端删除的情况，保留本地并报告不确定状态，不盲目重建远端文件。状态损坏时保留内容并报错，不以清空队列恢复。

## 4. 自动下载到 App 本地目录

启用同步并可访问原账号时，NSMetadataQuery 发现当前范围的云端附件。组件自动请求下载，待内容可读后在协调读取期间复制到本地 staging，校验后安装到 Files。大文件使用流式复制并限制并发。

自动下载覆盖受管理范围内的新文件；明确打开的文件优先于后台下载。不必由业务方逐个调用 download。App 挂起/终止、网络限制或设备空间不足时，后台复制不保证立即完成，下次获得执行机会后继续。

只有完成下载和本地提交后才报告“本地可用”。失败时保留已有本地内容并报告具体错误，不安装半个文件。收到占位信息也可以在列表显示“等待文件”，但 url(for:) 要等待本地文件就绪。

新路径自动接收。本地已有同路径不同内容、未完成写入、冲突版本或删除意图时暂停该文件并保留双方，不按修改时间直接覆盖。首版按不可变附件执行：不同字节都需要显式冲突处理和新路径导入，不自动原地安装另一份内容；使用期间延后下载/安装检查。

首次扫描尚未完成、离线空结果、账号切换或暂时无法查询，都不能作为远端删除证据。明确观察到的删除事件更新本地状态；跨重启缺少充分证据时标记待核实，保留本地且不重新上传。没有自定义远端删除协议时，不承诺所有情况下立即区分真实删除与暂时不可见。

## 5. 本地 URL 与使用期间保留

```swift
let url = try await files.url(for: file) // 始终是 Files 内的本地 URL
let data = try await files.read(file)   // 小文件
```

两个接口对来源透明。本地内容可用就直接返回，未下载完成时内部等待下载和复制，支持默认超时、取消及可选状态观察。不要求调用方先检查登录、下载或同步状态。单个调用方取消不影响其他等待者，取消等待也不保证系统取消传输。

url(for:) 不在每次调用时创建快照，也不会因为 iCloud 迁移而改变本地位置。但是 URL 本身不能表明调用方何时结束使用，普通返回不保证文件永远不被明确删除或更新；应用容器路径也不应跨安装/恢复持久化。

阅读器、播放器采用显式使用句柄：

```swift
let access = try await files.open(file)
player.open(access.url)
// 持有 access，直到播放器真正结束文件访问。
await access.close()
```

open 原子完成本地可用检查并登记使用计数。句柄持有期间，组件不删除、替换或清理该文件，不额外生成快照；close 幂等，最后一个句柄结束后重新检查云端内容并处理物理删除。此保证覆盖组件发起的操作，不包括调用方绕过组件修改文件或外部卸载/破坏。

远端/本机删除发生时先持久化并从正常列表隐藏，禁止新 open；已有句柄仍可读，物理清理延期。需要延迟的更新保存在 staging/deferred 或之后重新下载，不能覆盖正在使用的字节。更新延后期间的新句柄使用同一已安装版本并可观察待更新状态；明确冲突则报告冲突。

App 退出后原使用句柄不再有效，重启时无需恢复使用计数，但恢复延后操作。调用方必须使用 close 结束访问，不能只根据裸 URL 猜测使用期。read 的内部短期访问也计入保护。exportCopy 仅用于用户明确需要独立生命周期的副本，由调用方自行清理。

## 6. 无账号、配额不足、开关与账号切换

| 场景 | 本地行为 | 同步行为 |
|---|---|---|
| 初次未登录或容器不可用 | 正常保存、读取已有文件 | 保留明确待办 |
| 原账号可用 | 已有文件和 URL 保持不动 | 上传明确新增，自动下载远端文件 |
| iCloud 配额不足 | 本地保存继续、原件保留 | 显示失败/等待空间，降低交付频率 |
| 本机空间不足 | 无法提交的新保存报错 | 下载/安装失败不破坏已有内容 |
| 原账号退出 | 本地文件继续可读、新文件可保存 | 暂停原账号云操作 |
| 切换至另一账号 | 保留旧 scope 本地内容 | 不向新账号发送旧文件或删除 |
| iCloudEnabled 为 false | 本地读写、URL 和 open 正常 | 不启动云查询、交付、下载或云删除 |

iCloudEnabled 为实例初始化配置，首版不提供运行中 setter。关闭再重新打开同一存储范围时可继续使用全部已同步到本地的文件。关闭期间明确创建的文件仍记录其来源，重新启用并通过账号检查后可以上传；下载副本不会重新变成待上传。

开关只控制组件，不能停止已经交给系统的传输，不删除云端文件。尚未下载的文件在关闭时不可取到，但已下载本地文件不受影响。

宿主启用自动同步后首次可用时绑定账号；后续退出期间新增仍归原账号。不同账号需要独立 scope 和对应业务上下文，迁移数据必须显式导出再导入。身份变化废弃旧查询与容器 URL，取消旧任务，在回调及异步恢复时复查会话。后台旧账号结果不能写入新账号本地范围。

云端配额不足和本机磁盘不足分别映射实际 Foundation 错误。不能假定满配额时容器写入一定成功，也不把网络恢复当作配额恢复。已进入容器的文件由系统安排重试，尚未进入的明确新增由组件重试。上传、下载、删除独立处理，一个方向的错误不整体阻断其他方向。[Apple iCloud 错误](https://developer.apple.com/documentation/foundation/icloud-error-codes)

## 7. 删除、更新和防止旧文件重新上传

只有显式 importFile/write/registerFile 或调用方明确提交的历史导入产生上传意图。磁盘上存在文件、云端查询未发现文件、下载副本被更新，都不会生成上传意图。

remove 先持久化删除意图，取消未执行的上传并隐藏文件，再处理本地清理与原账号云删除。使用句柄存在时延期本地物理清理；云删除不可用或失败时保留待办，原账号恢复后重试。可证明未曾交付且没有远端对应项的新增只需本地删除。

远端明确删除也会隐藏本地文件并安排清理，但不反向产生上传。删除与下载安装、上传交付须按文件串行核对操作 generation，过期的下载结果不可复活已删除文件；同时发生的交付可能需要后续补删。

只维护本机意图和观察结果，不同步 tombstone，不承诺所有设备立即删除或删除永远战胜并发新写入。未知远端状态不冒充成功。保留记录的清理必须以操作完成及无后续恢复需求为前提，不任意按时间丢弃。

正常库不提供清理未上传原件的缓存淘汰。首版只提供可选的容器本机副本驱逐：已上传且无冲突时通过系统 API 请求释放容器缓存，本地 Files 内容仍保留；系统可能再次下载，不保证能长期维持一份磁盘占用。清理 Files 本地内容需遵循使用保护和明确操作语义。

## 8. 业务关联与 API

文件与业务数据库没有共同事务。新增先保存文件再提交引用；替换先保存新路径再切换引用；删除先移除业务引用再请求删文件。两步之间崩溃可能留下孤儿内容，需要业务方自己保留清理任务；组件不会扫描 SwiftStore 自动判定无引用文件。

核心 API 草案：

```swift
init(
    rootPath: String = "",
    iCloudEnabled: Bool = true,
    containerIdentifier: String? = nil
) async throws

var localRootURL: URL { get }
func importFile(from sourceURL: URL, path: String? = nil) async throws -> FileReference
func registerFile(path: String) async throws -> FileReference
func registerDirectory(path: String = "", recursive: Bool = true) async throws -> [FileReference]
func url(for file: FileReference, timeout: Duration = .seconds(30)) async throws -> URL
func open(_ file: FileReference, timeout: Duration = .seconds(30)) async throws -> FileAccess
func read(_ file: FileReference) async throws -> Data
func remove(_ file: FileReference) async throws -> DeletionResult
```

FileAccess 提供只读 url 和幂等异步 close。write 使用与 importFile 一致的 path 规则。其他 API 包括 list、status、events、download（提高优先级/显式等待）、exportCopy、retryPendingOperations、waitUntilUploaded、conflicts。同步状态观察为可选，基础读写不依赖它。

状态至少区分本地可用、下载/安装中、待交付、等待上传、上传完成、配额错误、冲突、账号不匹配、待删除/使用结束后清理。本地保存成功不代表已上传，上传完成不代表其他设备已安装到其本地目录。

## 9. 实现与验收

iCloud 容器访问使用 NSFileCoordinator / NSFilePresenter；NSMetadataQuery 由带 run loop 的适配器管理，查询默认 data scope。actor 管理状态，后台执行器负责大文件 I/O；不在协调回调里等待网络或上传完成。[Apple 协调要求](https://developer.apple.com/library/archive/technotes/tn2336/_index.html)

同一 scope 只允许一个写入实例，目录越界和重叠实例需要拒绝。状态有格式版本、原子更新和恢复路径，操作内容不能只保存在内存。新保存与下载安装要分别标明来源，系统状态可以重新查询，业务意图不可凭目录扫描猜测。

启动、前台恢复、身份变化、metadata 更新、明确保存/删除和手动重试触发调度，限制并发并退避。宿主提供 iCloud Documents entitlement 与生命周期通知。系统负责容器网络传输，App 自己负责自动安装到 Files，App 未运行时不承诺后者持续执行。

验证包括：自定义 path 和空 rootPath；禁用同步完全本地；未登录保存和重启；云配额与本机磁盘不足；自动下载到本地；URL 始终来自 Files；多个使用句柄、删除/更新延后及 close；上传失败保留原件；下载不会触发上传；云端删除不会被缓存复活；错误和崩溃恢复；账号隔离；大文件内存有界；iOS 16 与双设备真实传输。

实现提供独立包及仓库 library product；生产代码和本地故障测试已加入。实现中的 list/status 是可抛错接口，evictCloudCache 明确表示只释放系统容器缓存，localDirectory 可覆盖默认本地存储基目录。仍需宿主签名、真实 iCloud 容器与双设备/满配额验证，不能把模拟器或本地适配器测试当作云端实测。

registerFile(path:) 用于 localRootURL 内已经写入完成的文件，原地登记，不复制或移动内容。localRootURL 已包含 rootPath。调用方关闭写入句柄后登记，之后不得直接修改已管理文件。重复登记相同内容保留原来源和同步状态，下载副本不会因此重新产生上传意图；路径越界、符号链接、缺失文件、内容冲突和已删除路径均拒绝。登记提交前退出会留下未登记文件，由调用方重试，组件不自动扫描上传。

registerDirectory(path:recursive:) 一次性扫描本地目录并逐文件登记，默认递归；空 path 表示 localRootURL。整批校验后原子提交登记记录，失败不留下部分新增登记。跳过隐藏项，拒绝符号链接、非法类型及冲突内容；空目录不单独同步。返回按相对路径排序的文件引用列表，不持续监听后续本地写入。
