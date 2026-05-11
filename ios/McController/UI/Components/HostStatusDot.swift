import SwiftUI

struct HostStatusDot: View {
    enum Status { case offline, online, busy, mcRunning }
    let status: Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(
                Circle().stroke(.white.opacity(0.35), lineWidth: 1)
            )
    }

    private var color: Color {
        switch status {
        case .offline:    return .gray
        case .online:     return .blue
        case .busy:       return .orange
        case .mcRunning:  return .green
        }
    }
}
