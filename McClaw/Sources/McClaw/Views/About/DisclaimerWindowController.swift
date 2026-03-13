import SwiftUI
import AppKit

/// Floating window that displays the legal disclaimer, following the LicenseWindowController pattern.
@MainActor
final class DisclaimerWindowController {
    static let shared = DisclaimerWindowController()
    private var window: NSWindow?

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let disclaimerView = NSHostingView(rootView: DisclaimerContentView())
        disclaimerView.frame = NSRect(x: 0, y: 0, width: 500, height: 600)

        let panel = NSPanel(
            contentRect: disclaimerView.frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = disclaimerView
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.minSize = NSSize(width: 400, height: 400)
        panel.makeKeyAndOrderFront(nil)

        window = panel
    }
}

// MARK: - Disclaimer Content View

private struct DisclaimerContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)

                Text(String(localized: "disclaimer_title", bundle: .module))
                    .font(.title2.weight(.semibold))

                Text("© 2024-2026 José Conti")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 20)

            // Disclaimer text
            ScrollView {
                Text(disclaimerText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(20)
            }
        }
        .frame(width: 500, height: 600)
    }

    private var disclaimerText: String {
        """
        DISCLAIMER

        Last updated: March 2026


        1. OPEN SOURCE SOFTWARE

        McClaw is free and open-source software released under the GNU General \
        Public License v3.0 (GPLv3). The complete source code is publicly \
        available at:

        https://github.com/joseconti/mc-claw

        You are free to inspect, modify, and redistribute this software in \
        accordance with the terms of the GPLv3 license.


        2. NO WARRANTY

        THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, \
        EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF \
        MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND \
        NONINFRINGEMENT.

        The author makes no representations or warranties regarding the \
        accuracy, reliability, completeness, or suitability of this software \
        for any particular purpose.


        3. LIMITATION OF LIABILITY

        IN NO EVENT SHALL THE AUTHOR, JOSÉ CONTI, OR ANY CONTRIBUTORS BE \
        LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR \
        CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF \
        SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR \
        BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, \
        WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE \
        OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, \
        EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


        4. THIRD-PARTY SERVICES

        McClaw interfaces with third-party command-line tools, APIs, and \
        services (including, but not limited to, Claude, ChatGPT, Gemini, and \
        Ollama). The author is not affiliated with, endorsed by, or \
        responsible for any of these third-party services.

        Your use of third-party services through McClaw is subject to the \
        respective terms of service and privacy policies of those providers. \
        The author assumes no responsibility for the availability, accuracy, \
        or conduct of any third-party service.


        5. USE AT YOUR OWN RISK

        You use this software entirely at your own risk. You are solely \
        responsible for any actions taken through McClaw, including but not \
        limited to commands executed, data transmitted, and configurations \
        applied.

        The author shall not be held responsible for any loss, damage, or \
        adverse consequence resulting from the use or inability to use this \
        software.


        6. NO PROFESSIONAL ADVICE

        The outputs generated through McClaw (via connected AI services) do \
        not constitute professional, legal, medical, financial, or any other \
        form of expert advice. Always consult a qualified professional for \
        matters requiring specialized expertise.


        7. DATA AND PRIVACY

        McClaw processes data locally on your device. However, when \
        interacting with third-party AI services, your data may be transmitted \
        to external servers governed by the privacy policies of those \
        providers. The author is not responsible for how third-party services \
        handle your data.


        By using McClaw, you acknowledge that you have read, understood, and \
        agreed to the terms of this disclaimer.
        """
    }
}
