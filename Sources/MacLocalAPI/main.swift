import ArgumentParser
import Foundation
import Darwin

// Global references for signal handling
private var globalServer: Server?
private var shouldKeepRunning = true

// Signal handler function
func handleShutdown(_ signal: Int32) {
    print("\n🛑 Received shutdown signal, shutting down...")
    globalServer?.shutdown()
    shouldKeepRunning = false
}

struct MacLocalAPI: ParsableCommand {
    static let buildVersion: String = {
        // Check if BuildVersion.swift exists with generated version
        return BuildInfo.version ?? "dev-build"
    }()
    
    static let configuration = CommandConfiguration(
        commandName: "afm",
        abstract: "macOS server that exposes Apple's Foundation Models through OpenAI-compatible API",
        discussion: "GitHub: https://github.com/scouzi1966/maclocal-api",
        version: buildVersion
    )
    
    @Option(name: .shortAndLong, help: "Port to run the server on")
    var port: Int = 9999
    
    @Flag(name: .shortAndLong, help: "Enable verbose logging")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Disable streaming responses (streaming is enabled by default)")
    var noStreaming: Bool = false
    
    @Option(name: [.short, .long], help: "Custom instructions for the AI assistant")
    var instructions: String = "You are a helpful assistant"
    
    @Option(name: [.customShort("s"), .long], help: "Run a single prompt without starting the server")
    var singlePrompt: String?
    
    func run() throws {
        // Handle single-prompt mode
        if let prompt = singlePrompt {
            return try runSinglePrompt(prompt)
        }
        
        // Check for piped input
        if let stdinContent = try readFromStdin() {
            return try runSinglePrompt(stdinContent)
        }
        
        if verbose {
            print("Starting afm server with verbose logging enabled...")
        }
        
        // Use RunLoop to handle the server lifecycle properly
        let runLoop = RunLoop.current
        
        // Set up signal handling for graceful shutdown
        signal(SIGINT, handleShutdown)
        signal(SIGTERM, handleShutdown)
        
        // Start server in async context
        _ = Task {
            do {
                let server = try await Server(port: port, verbose: verbose, streamingEnabled: !noStreaming, instructions: instructions)
                globalServer = server
                try await server.start()
            } catch {
                print("Error starting server. CTRL-C to stop: \(error)")
                shouldKeepRunning = false
            }
        }
        
        // Keep the main thread alive until shutdown
        while shouldKeepRunning && runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1)) {
            // Keep running until shutdown signal
        }
        
        print("Server shutdown complete.")
    }
    
    private func readFromStdin() throws -> String? {
        // Check if stdin is connected to a terminal (not piped)
        guard isatty(STDIN_FILENO) == 0 else {
            return nil
        }
        
        let stdin = FileHandle.standardInput
        let maxInputSize = 1024 * 1024 // 1MB limit
        var inputData = Data()
        
        // Read all available data from stdin
        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty {
                break
            }
            
            inputData.append(chunk)
            
            // Prevent excessive memory usage
            if inputData.count > maxInputSize {
                print("Error: Input too large (max 1MB)")
                throw ExitCode.failure
            }
        }
        
        // Convert to string and validate
        guard let content = String(data: inputData, encoding: .utf8) else {
            print("Error: Invalid UTF-8 input. Binary data not supported.")
            throw ExitCode.failure
        }
        
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for empty input
        guard !trimmedContent.isEmpty else {
            print("Error: Empty input received from pipe")
            throw ExitCode.failure
        }
        
        return trimmedContent
    }
    
    private func runSinglePrompt(_ prompt: String) throws {
        let group = DispatchGroup()
        var result: Result<String, Error>?
        
        group.enter()
        Task {
            do {
                if #available(macOS 26.0, *) {
                    let foundationService = try await FoundationModelService(instructions: instructions)
                    let message = Message(role: "user", content: prompt)
                    let response = try await foundationService.generateResponse(for: [message])
                    result = .success(response)
                } else {
                    result = .failure(FoundationModelError.notAvailable)
                }
            } catch {
                result = .failure(error)
            }
            group.leave()
        }
        
        group.wait()
        
        switch result {
        case .success(let response):
            print(response)
        case .failure(let error):
            if let foundationError = error as? FoundationModelError {
                print("Error: \(foundationError.localizedDescription)")
            } else {
                print("Error: \(error.localizedDescription)")
            }
            throw ExitCode.failure
        case .none:
            print("Error: Unexpected error occurred")
            throw ExitCode.failure
        }
    }
}

MacLocalAPI.main()