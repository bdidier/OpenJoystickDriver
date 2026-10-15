import Foundation

/// The physical-controller path: the pipeline reads and parses a controller's reports and sends
/// the frames to the dispatcher it was built with.
extension DevicePipeline: InputSource {
  nonisolated var origin: InputOrigin { .physicalController }
  nonisolated var sink: any OutputSink { dispatcher }
}
