import Foundation
import MapleCore
import SwiftUI
import Testing
@testable import MapleDesign

@Suite("Notifications primer")
@MainActor
struct NotificationsPrimerTests {
    @Test("The primer names the only reminder, in two calm sentences")
    func copy() {
        let message = NotificationsPrimerView.message
        #expect(message.split(separator: ".").count == 2)
        #expect(message.contains("wind down"))
        #expect(!message.contains("leaf") && !message.contains("morning"))
        #expect(message.hasSuffix("Nothing else."))
        #expect(NotificationsPrimerView.title == "A gentle reminder")
        for line in [NotificationsPrimerView.title, message, NotificationsPrimerView.allowTitle, NotificationsPrimerView.notNowTitle] {
            #expect(!line.contains("!"))
            #expect(line.first?.isUppercase == true)
        }
        #expect(NotificationsPrimerView.allowTitle == "Allow reminders")
        #expect(NotificationsPrimerView.notNowTitle == "Not now")
    }

    @Test("It renders on a sheet and on a full screen, with a leaf or with words alone")
    func renders() throws {
        let saccharum = try #require(LeafCatalog.shared.species(id: RewardCatalog.shared.rungs(in: .firstSteps)[0].speciesID))
        let views: [AnyView] = [
            AnyView(NotificationsPrimerView(species: saccharum, colourway: .autumn, onAllow: {}, onNotNow: {})),
            AnyView(NotificationsPrimerView(isAsking: true, page: .black, onAllow: {}, onNotNow: {})),
        ]
        for view in views {
            let renderer = ImageRenderer(content: view.frame(width: 402, height: 420).background(Color.black))
            renderer.scale = 1
            #expect(renderer.cgImage != nil)
        }
    }
}
