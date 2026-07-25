import SwiftUI

struct SettingsView: View {
    @AppStorage("readingWidth") private var readingWidth = 760.0
    @AppStorage("baseFontSize") private var baseFontSize = 16.0

    var body: some View {
        Form {
            LabeledContent("Text size") {
                Slider(value: $baseFontSize, in: 13...24, step: 1)
                    .frame(width: 220)
                Text("\(Int(baseFontSize)) pt")
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }

            LabeledContent("Reading width") {
                Slider(value: $readingWidth, in: 520...1_100, step: 20)
                    .frame(width: 220)
                Text("\(Int(readingWidth))")
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 470)
    }
}
