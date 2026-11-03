/// Photo vs. video changes session topology (movie output + microphone input
/// vs. photo output), so it lives in CaptureConfiguration alongside
/// position/lensType rather than as separate ViewModel-only state.
enum CaptureMode: String, CaseIterable, Hashable {
    case photo
    case video
}
