import AppKit

/// The standard About panel, with the data credits, licenses and notes every source asks for.
@MainActor
enum AboutPanel {
    static func show() {
        let credits = CreditsText()
        credits.heading("Data")
        credits.line("Live aircraft positions: ", link: "adsb.lol", "https://adsb.lol", then: " and ")
        credits.link("adsb.fi", "https://adsb.fi", then: ", from community ADS-B receivers.\n")
        credits.line("Routes, airframes and airline names: ", link: "adsbdb.com", "https://www.adsbdb.com", then: ".\n")
        credits.line("Map: ", link: "Natural Earth", "https://www.naturalearthdata.com", then: " and ")
        credits.link("OurAirports", "https://ourairports.com", then: " (public domain). Apple Map style: © Apple Maps.\n")
        credits.heading("Please note")
        credits.text("Airspace isn't affiliated with or endorsed by these services, any airline or the FAA. Positions can be late, wrong or missing; don't use it for navigation or safety.\n")
        credits.heading("Privacy")
        credits.text("The flight-data services get only the map center, rounded to about a kilometer. Nothing is sent to the developer. ")
        credits.link("Privacy policy", "https://grantkovich.com/privacy/", then: "\n")
        credits.heading("Made by")
        credits.link("Grant Kovich", "https://grantkovich.com", then: " · ")
        credits.link("Feedback", "https://grantkovich.com/contact/", then: "")
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits.string])
    }
}

/// Small builder for the About panel's credits.
@MainActor
final class CreditsText {
    let string = NSMutableAttributedString()
    private let body: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        .foregroundColor: NSColor.labelColor,
    ]

    func heading(_ s: String) {
        if string.length > 0 { string.append(NSAttributedString(string: "\n", attributes: body)) }
        string.append(NSAttributedString(string: s + "\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
        ]))
    }

    func text(_ s: String) { string.append(NSAttributedString(string: s, attributes: body)) }

    func link(_ title: String, _ url: String, then: String) {
        var attrs = body
        attrs[.link] = URL(string: url)
        string.append(NSAttributedString(string: title, attributes: attrs))
        text(then)
    }

    func line(_ lead: String, link title: String, _ url: String, then: String) {
        text(lead)
        link(title, url, then: then)
    }
}
