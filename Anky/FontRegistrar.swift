import CoreText
import Foundation

enum FontRegistrar {
    static func registerBundledFonts() {
        register(resource: "Righteous-Regular", withExtension: "ttf", subdirectory: "Fonts")
    }

    private static func register(resource: String, withExtension ext: String, subdirectory: String?) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: subdirectory) else {
            return
        }

        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
