import SwiftUI

struct LogPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var logLines: [String] = []
    @State private var autoFollow = true
    @State private var logTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(appState.activeLogName ?? "Logs")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                if !appState.isLogServerRunning {
                    Text("Server stopped")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }

                Button { autoFollow.toggle() } label: {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(autoFollow ? .accentColor : .secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(autoFollow ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(autoFollow ? "Auto-follow on" : "Auto-follow off")

                IconButton(icon: "xmark", help: "Close") {
                    appState.closeLog()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if logLines.isEmpty {
                            Text("No logs available")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(logLines.indices, id: \.self) { idx in
                                Text(logLines[idx])
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .id(idx)
                            }
                        }
                    }
                    .padding(12)
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .onChange(of: logLines.count) { _ in
                    guard autoFollow, let last = logLines.indices.last else { return }
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            autoFollow = true
            startLogTask()
        }
        .onDisappear {
            logTask?.cancel()
            logTask = nil
        }
        .onChange(of: appState.activeLogPath) { _ in
            autoFollow = true
            startLogTask()
        }
    }

    private func startLogTask() {
        logTask?.cancel()
        logTask = Task {
            while !Task.isCancelled {
                if let path = appState.activeLogPath {
                    let lines = LogReader.tailFile(at: path, lines: 1000)
                    logLines = lines
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}

struct LogReader {
    private static let ansiPattern = try! NSRegularExpression(pattern: "\\x1B\\[[0-9;]*[A-Za-z]")

    static func tailFile(at path: String, lines lineCount: Int = 1000) -> [String] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        guard fileSize > 0 else { return [] }

        let chunkSize: UInt64 = 65536
        var offset = fileSize
        var chunks: [Data] = []
        var newlineCount = 0

        while offset > 0 && newlineCount <= lineCount {
            let readSize = min(chunkSize, offset)
            offset -= readSize
            handle.seek(toFileOffset: offset)
            let chunk = handle.readData(ofLength: Int(readSize))
            chunks.append(chunk)
            newlineCount += chunk.filter { $0 == UInt8(ascii: "\n") }.count
        }

        chunks.reverse()
        let combined = chunks.reduce(Data()) { $0 + $1 }
        guard let text = String(data: combined, encoding: .utf8) else { return [] }

        var allLines = text.components(separatedBy: "\n")
        if allLines.last?.isEmpty == true { allLines.removeLast() }
        return Array(allLines.suffix(lineCount)).map { stripAnsi($0) }
    }

    static func stripAnsi(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return ansiPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
