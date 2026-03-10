import SwiftUI

/// Animated thinking indicator that types out fun words letter by letter while McClaw is processing.
/// Inspired by Claude Code's "clauding/cooking" thinking tokens typewriter effect.
struct ThinkingWordsView: View {
    @State private var currentWord = ThinkingWords.random()
    @State private var visibleCount = 0
    @State private var phase: TypewriterPhase = .typing
    @State private var typingTask: Task<Void, Never>?

    private enum TypewriterPhase {
        case typing    // Letters appearing one by one
        case holding   // Full word visible, pause before erasing
        case erasing   // Letters disappearing one by one
        case picking   // Choosing next word
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.6)

            Text(String(currentWord.prefix(visibleCount)))
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
            + Text(phase == .typing || phase == .erasing ? "▌" : "")
                .font(.body)
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .onAppear { startTypewriter() }
        .onDisappear { typingTask?.cancel() }
    }

    private func startTypewriter() {
        typingTask?.cancel()
        typingTask = Task { @MainActor in
            while !Task.isCancelled {
                // Type in letter by letter
                phase = .typing
                let chars = currentWord.count
                for i in 1...chars {
                    guard !Task.isCancelled else { return }
                    visibleCount = i
                    try? await Task.sleep(for: .milliseconds(Int.random(in: 45...90)))
                }

                // Hold the full word for a moment
                phase = .holding
                try? await Task.sleep(for: .milliseconds(Int.random(in: 1500...2500)))
                guard !Task.isCancelled else { return }

                // Erase letter by letter (faster than typing)
                phase = .erasing
                for i in stride(from: chars, through: 0, by: -1) {
                    guard !Task.isCancelled else { return }
                    visibleCount = i
                    try? await Task.sleep(for: .milliseconds(Int.random(in: 25...50)))
                }

                // Pick next word
                phase = .picking
                currentWord = ThinkingWords.random(excluding: currentWord)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
}

/// Collection of fun thinking words for McClaw's processing indicator.
enum ThinkingWords {
    private static let words: [String] = [
        // Claw/cat themed
        "Clawing...",
        "Pawsing...",
        "Scratching...",
        "Purring...",
        "Meowzing...",
        "Whiskers tingling...",
        "Sharpening claws...",
        "Cat-culating...",
        "Pouncing...",
        "Fur-mulating...",
        "Tail-spinning...",
        "Napping... jk",
        "Grooming bytes...",
        "Chasing laser...",
        "Kneading data...",
        "Hissing...",
        "Prowling...",
        "Nuzzling...",
        "Whisking...",
        "Paw-processing...",
        "Fur-bishing...",
        "Litter-ating...",
        "Catnapping...",
        "Yarn-balling...",
        "Mouse-hunting...",
        "Stretching...",
        "Arching back...",
        "Tail-flicking...",
        "Toe-beaning...",
        "Belly-flopping...",
        "Claw-crafting...",
        "Whisker-twitching...",
        "Mew-sing...",
        "Kit-tenizing...",
        "Fur-menting...",

        // Tech/AI gerundios
        "Tokenizing...",
        "Crunching...",
        "Parsing...",
        "Synapsing...",
        "Embedding...",
        "Attention-ing...",
        "Transforming...",
        "Backpropagating...",
        "Softmaxing...",
        "Inferencing...",
        "Hallucin— nah...",
        "Hashing...",
        "Forking...",
        "Piping...",
        "Streaming...",
        "Buffering...",
        "Compiling...",
        "Diffing...",
        "Rebasing...",
        "Linting...",
        "Shimming...",
        "Vectorizing...",
        "Quantizing...",
        "Fine-tuning...",
        "Normalizing...",
        "Gradient-ing...",
        "Batch-norming...",
        "Dropout-ing...",
        "Pooling...",
        "Convolving...",
        "Denoising...",
        "Decoding...",
        "Encoding...",
        "Latent-spacing...",
        "Weight-shifting...",
        "Loss-reducing...",
        "Epoch-ing...",
        "Checkpointing...",
        "Serializing...",
        "Deserializing...",
        "Sharding...",
        "Sampling...",

        // Nonsense / inventados divertidos
        "Chuning...",
        "Bibbing...",
        "Puttering...",
        "Churning...",
        "Noodling...",
        "Whirring...",
        "Fizzing...",
        "Buzzing...",
        "Zapping...",
        "Blorping...",
        "Snarfing...",
        "Glurping...",
        "Skronking...",
        "Flumping...",
        "Wibbling...",
        "Zonking...",
        "Snurfing...",
        "Bipping...",
        "Dinking...",
        "Plonking...",
        "Thunking...",
        "Blipping...",
        "Skibbling...",
        "Frobbing...",
        "Twiddling...",
        "Murfing...",
        "Gnarling...",
        "Splooting...",
        "Booping...",
        "Flonking...",
        "Sprocking...",
        "Glitching...",
        "Yonking...",
        "Schmoozing...",
        "Wrangling...",
        "Faffing...",
        "Nerfing...",
        "Bonking...",
        "Doodling...",
        "Scooching...",
        "Squishing...",
        "Wonking...",
        "Kerfluffling...",
        "Bamboozling...",
        "Discombobulating...",
        "Flibberting...",
        "Gobsmacking...",
        "Jiggering...",
        "Kerfuffling...",
        "Lollygagging...",
        "Moseying...",
        "Persnicketing...",
        "Rigmarole-ing...",
        "Skullduggering...",
        "Widdershining...",
        "Cattywampusing...",

        // Verbos reales divertidos
        "Cooking...",
        "Brewing...",
        "Simmering...",
        "Marinating...",
        "Conjuring...",
        "Pondering...",
        "Ruminating...",
        "Scheming...",
        "Tinkering...",
        "Fiddling...",
        "Mulling...",
        "Musing...",
        "Hatching...",
        "Percolating...",
        "Gestating...",
        "Fermenting...",
        "Daydreaming...",
        "Perusing...",
        "Rummaging...",
        "Spelunking...",
        "Gallivanting...",
        "Meandering...",
        "Navel-gazing...",
        "Wool-gathering...",
        "Mind-wandering...",
        "Cogitating...",
        "Deliberating...",
        "Contemplating...",
        "Brainstorming...",
        "Philosophizing...",
        "Overthinking...",
        "Manifesting...",
        "Improvising...",
        "Riffing...",
        "Jamming...",
        "Scribbling...",
        "Doodling...",
        "Whittling...",
        "Tenderizing...",
        "Seasoning...",
        "Basting...",
        "Kneading...",
        "Whisking...",
        "Steeping...",
        "Distilling...",
        "Decanting...",
        "Pickling...",
        "Curing...",

        // McClaw / CLI style
        "McClawing...",
        "McCrunching...",
        "McThinking...",
        "McBrewing...",
        "McParsing...",
        "McStreaming...",
        "CLI-whispering...",
        "Shell-diving...",
        "Pipe-dreaming...",
        "Sudo-ing...",
        "Grep-ping...",
        "Awk-warding...",
        "Sed-ucing...",
        "Curl-ing...",
        "Ssh-hing...",
        "Git-ting...",
        "Chmod-ing...",
        "Ping-ing...",
        "Npm-ing...",
        "Yarn-ing...",
        "Docker-ing...",
        "Kubectl-ing...",
        "Vim-ing...",
        "Nano-ing...",
        "Bash-ing...",
        "Zsh-elling...",
        "Brew-installing...",
        "Stack-overflowing...",
        "Rubber-ducking...",
    ]

    static func random() -> String {
        words.randomElement() ?? "Thinking..."
    }

    static func random(excluding current: String) -> String {
        let filtered = words.filter { $0 != current }
        return filtered.randomElement() ?? "Thinking..."
    }
}
