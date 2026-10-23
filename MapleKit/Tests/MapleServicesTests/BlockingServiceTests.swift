import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("Blocking service")
@MainActor
struct BlockingServiceTests {
    private let session = UUID()

    @Test("The tier comes from Info.plist; anything unexpanded or missing is free")
    func tier() {
        #expect(MapleBuild.tier(infoValue: "paid") == .paid)
        #expect(MapleBuild.tier(infoValue: "free") == .free)
        #expect(MapleBuild.tier(infoValue: nil) == .free)
        #expect(MapleBuild.tier(infoValue: "$(MAPLE_TIER)") == .free)
        #expect(MapleBuild.capability(tier: .free, usesPreview: true) == .preview)
        #expect(MapleBuild.capability(tier: .free, usesPreview: false) == .unavailableInBuild)
        #expect(MapleBuild.capability(tier: .paid, usesPreview: false) == .unavailableInBuild)
    }

    @Test("A build that can't block says so and never claims a shield")
    func unavailable() async {
        let service = UnavailableBlockingService()
        #expect(service.capability == .unavailableInBuild)
        #expect(await service.probe() == .unavailable)
        #expect(await service.requestAuthorization() == .unavailable)
        let result = await service.perform(.apply(session: session), selection: Data("x".utf8))
        #expect(!result.isVerified)
        #expect(result.failure == .notAllowed)
        #expect(await service.readStore() == .empty)
    }

    @Test("The preview blocker applies, verifies and clears, reading back each time")
    func preview() async {
        let service = PreviewBlockingService(authorization: .notDetermined)
        #expect(service.source == .preview)
        #expect(await service.probe() == .notDetermined)
        #expect(await service.requestAuthorization() == .allowed)
        #expect(await service.perform(.apply(session: session), selection: Data("x".utf8)) == ShieldResult(store: .applied(session: session)))
        #expect(await service.perform(.verify(session: session), selection: nil).isVerified)
        #expect(await service.perform(.clear(session: session), selection: nil) == ShieldResult(store: .empty))
        #expect(service.operations == [.apply(session: session), .verify(session: session), .clear(session: session)])
        #expect(await service.releaseAll().isVerified)
    }

    @Test("Each real failure mode reads back as a failure")
    func failures() async {
        let overflow = PreviewBlockingService(failures: [.tokenOverflow])
        let full = await overflow.perform(.apply(session: session), selection: Data("x".utf8))
        #expect(full == ShieldResult(store: .empty, failure: .readBack))

        let failing = PreviewBlockingService(failures: [.applyFails])
        #expect(await failing.perform(.apply(session: session), selection: Data("x".utf8)).failure == .applyFailed)

        let expired = PreviewBlockingService(failures: [.expiredTokens])
        #expect(await expired.perform(.apply(session: session), selection: Data("x".utf8)).failure == .expiredTokens)

        let declined = PreviewBlockingService(authorization: .declined)
        #expect(await declined.perform(.apply(session: session), selection: Data("x".utf8)).failure == .notAllowed)

        // Revoked mid-session: the status still says allowed, but the shields are gone on the next read-back.
        let revoked = PreviewBlockingService()
        _ = await revoked.perform(.apply(session: session), selection: Data("x".utf8))
        revoked.revoke()
        #expect(await revoked.probe() == .allowed)
        #expect(await revoked.perform(.verify(session: session), selection: nil) == ShieldResult(store: .empty, failure: .readBack))
        #expect(await revoked.readStore() == .empty)
    }
}
