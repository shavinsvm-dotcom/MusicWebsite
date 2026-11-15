import SwiftUI

enum DownloadJobState: String, Equatable {
    case queued
    case downloading
    case completed
    case failed
    case cancelled

    var title: String {
        switch self {
        case .queued: return "Queued"
        case .downloading: return "Downloading"
        case .completed: return "Downloaded"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

struct DownloadJob: Identifiable, Equatable {
    let id: UUID
    let trackID: UUID
    let title: String
    let artist: String
    var state: DownloadJobState
    var detail: String?
    let createdAt: Date
}

struct DownloadManagerView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if library.downloadJobs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No downloads yet")
                            .font(.headline)
                        Text("Cloud songs you download will appear here with their progress.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(library.downloadJobs) { job in
                            DownloadJobRow(job: job)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(AppBackground())
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if library.downloadJobs.contains(where: { $0.state == .completed || $0.state == .cancelled }) {
                        Button("Clear") {
                            library.clearFinishedDownloads()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct DownloadJobRow: View {
    @EnvironmentObject private var library: LibraryStore
    let job: DownloadJob

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(job.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(job.detail ?? job.state.title)
                    .font(.caption2)
                    .foregroundStyle(job.state == .failed ? .red.opacity(0.85) : .tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            actions
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var icon: some View {
        switch job.state {
        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .downloading:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red.opacity(0.85))
        case .cancelled:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch job.state {
        case .queued, .downloading:
            Button("Cancel", role: .destructive) {
                library.cancelDownload(job.id)
            }
            .font(.caption.weight(.semibold))
        case .failed, .cancelled:
            HStack(spacing: 10) {
                Button("Retry") {
                    library.retryDownload(job)
                }
                .font(.caption.weight(.semibold))

                Button("Remove", role: .destructive) {
                    library.removeDownloadJob(job.id)
                }
                .font(.caption)
            }
        case .completed:
            Button("Remove", role: .destructive) {
                library.removeDownloadJob(job.id)
            }
            .font(.caption)
        }
    }
}
