import Foundation

// 复现 ChatStoreTests 的崩溃模式:
//   1. 测试用 UserDefaults(suiteName: #function) 建了一个 suite 实例
//   2. StorageService.setAsync 用 Task.detached 捕获 defaults,再 MainActor.run 写入
//   3. 测试方法结束 -> StorageService 被释放 -> Task 析构时在 executor 上释放捕获的 defaults

final class StorageServiceLike: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let encoder = JSONEncoder()

    init(defaults: UserDefaults) { self.defaults = defaults }

    func setAsync<T: Codable>(_ key: String, value: T) {
        let fullKey = key
        let defaultsRef = defaults
        Task.detached(priority: .utility) {
            await withTaskCancellationHandler {
                do {
                    let data = try Self.encoder.encode(value)
                    await MainActor.run {
                        defaultsRef.set(data, forKey: fullKey)
                    }
                } catch {
                    FileHandle.standardError.write("encode error: \(error)\n".data(using: .utf8)!)
                }
            } onCancel: {
                FileHandle.standardError.write("cancelled\n".data(using: .utf8)!)
            }
        }
    }
}

func makeSuite() -> UserDefaults {
    UserDefaults(suiteName: "setUp()")!
}

let iterations = Int(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "200") ?? 200
var failures = 0

for i in 0..<iterations {
    let suite = makeSuite()
    let svc = StorageServiceLike(defaults: suite)
    svc.setAsync("chatSessions", value: [["id": "x\(i)"]])
    // 立刻释放 service 与 suite,模拟测试方法结束
    autoreleasepool {
        _ = svc
    }
    if i % 50 == 0 { print("iteration \(i)") }
}

// 给后台 task 时间收尾
RunLoop.current.run(until: Date().addingTimeInterval(3))
print("done, failures=\(failures)")
