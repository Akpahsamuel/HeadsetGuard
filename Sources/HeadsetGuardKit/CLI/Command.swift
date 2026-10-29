import Foundation

public enum Command: Equatable {
    case help
    case status
    case list
    case lock
    case unlock
    case disconnect
    case setPassword
    case logs
    case unknown(String)
    case app

    public static func parse(_ args: [String]) -> Command {
        guard let first = args.first else {
            return .app
        }
        switch first {
        case "--help", "-h":
            return .help
        case "--status":
            return .status
        case "--list":
            return .list
        case "--lock":
            return .lock
        case "--unlock":
            return .unlock
        case "--disconnect":
            return .disconnect
        case "--set-password":
            return .setPassword
        case "--logs":
            return .logs
        default:
            return .unknown(first)
        }
    }
}
