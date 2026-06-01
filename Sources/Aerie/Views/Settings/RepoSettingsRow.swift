import SwiftUI

/// A single repository row inside the Settings → Repositories list.
///
/// Visual contract: `docs/superpowers/design/v2/settings.jsx` lines 257-305
/// (`RepoSettingsRow`). A 5-column grid — `18px 1fr 1.3fr 130px 28px`, 18 pt
/// column gap, vertically centred, 16×20 pt padding:
///   ┌──────────────────────────────────────────────────────────────┐
///   │ ⠿  <name>            <owner/repo>           <avatar> acct   × │
///   │    ~/path            ⌥ <branch>                              │
///   └──────────────────────────────────────────────────────────────┘
///
/// The `⠿` grip carries a `DragGesture`: it forwards its cumulative vertical
/// translation to the list (`RepositoriesScreen`), which owns the reorder maths
/// and persistence. Scoping the gesture to the grip keeps the rest of the row
/// (account menu, remove button) clickable. The "current branch" + dirty/behind
/// dots from the design mock are omitted: the Settings repo model only carries
/// `defaultBranch`, not live git state, so we render that single branch.
struct RepoSettingsRow: View {
    let repo: Repository
    let accounts: [GitHubAccount]
    /// True while this row is the one being dragged — keeps the grip lit so the
    /// user can see what they've grabbed.
    var isDragging: Bool = false
    var onChangeAccount: (UUID) -> Void
    var onRemove: () -> Void
    /// Reports the grip's cumulative vertical drag translation (points). The
    /// list owns the reorder maths; the row just forwards the gesture.
    var onDragChange: (CGFloat) -> Void = { _ in }
    var onDragEnd: () -> Void = {}

    @State private var gripHover = false

    var body: some View {
        HStack(spacing: 18) {
            grip
            nameAndPath
                .frame(maxWidth: .infinity, alignment: .leading)
            githubAndBranch
                .frame(maxWidth: .infinity, alignment: .leading)
            accountPicker
                .frame(width: 130, alignment: .leading)
            removeButton
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Pieces

    // `⠿` braille grip, text-4 — `settings.jsx` line 268. Drag it to reorder;
    // the gesture lives only on the grip (taller hit area than the glyph) so the
    // rest of the row stays clickable. Brightens on hover / while dragging.
    private var grip: some View {
        Text("⠿")
            .font(.system(size: 14))
            .foregroundStyle(isDragging || gripHover ? AerieColor.text2 : AerieColor.text4)
            .frame(width: 18, height: 32, alignment: .center)
            .contentShape(Rectangle())
            .onHover { gripHover = $0 }
            .help("Drag to reorder")
            // `coordinateSpace: .global` is critical: the list moves the dragged
            // row with `.offset`, and this grip rides inside that row. With the
            // default `.local` space the gesture measures translation against the
            // row's OWN (moving) origin, so the offset feeds back into the
            // translation and the row oscillates violently. Global space is fixed
            // to the screen, so translation reflects only real finger movement.
            // (The window no longer background-drags — see `AerieWindowChrome` —
            // so a normal distance threshold cleanly separates drag from click.)
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { onDragChange($0.translation.height) }
                    .onEnded { _ in onDragEnd() }
            )
            .animation(.easeOut(duration: 0.12), value: gripHover)
    }

    private var nameAndPath: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(repo.name)
                .aerieFont(AerieFont.custom(.sans, size: 14.5).weight(.medium))
                .foregroundStyle(AerieColor.text1)
                .lineLimit(1)
            Text(collapsedPath(repo.localPath.path))
                .aerieFont(AerieFont.code(11.5))
                .foregroundStyle(AerieColor.text3)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var githubAndBranch: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(repo.githubOwner)/\(repo.githubRepo)")
                .aerieFont(AerieFont.code(12.5))
                .foregroundStyle(AerieColor.text2)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 8) {
                BranchGlyph()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(AerieColor.text4)
                Text(repo.defaultBranch)
                    .aerieFont(AerieFont.code(11.5))
                    .foregroundStyle(AerieColor.text3)
                    .lineLimit(1)
            }
        }
    }

    // Avatar + account login. Click opens a picker to reassign the repo's
    // primary account (the design mock is static; we keep it actionable).
    // The avatar sits OUTSIDE the `Menu` on purpose — SwiftUI's borderless
    // `Menu` only renders a plain Text label in headless snapshots (it drops
    // non-text/background content), so an avatar inside the label would vanish
    // from snapshots. Outside, it always paints; the Menu wraps just the login.
    private var accountPicker: some View {
        HStack(spacing: 8) {
            if let acc = accounts.first(where: { $0.id == repo.primaryAccountId }) {
                AccountAvatar(login: acc.login, size: 18)
                accountMenu(label: acc.login, color: AerieColor.text2)
            } else {
                Circle()
                    .fill(AerieColor.glass3)
                    .frame(width: 18, height: 18)
                accountMenu(label: "(none)", color: AerieColor.text4)
            }
        }
    }

    private func accountMenu(label: String, color: Color) -> some View {
        Menu {
            ForEach(accounts) { account in
                Button("\(account.login) @ \(account.host)") {
                    onChangeAccount(account.id)
                }
            }
        } label: {
            Text(label)
                .aerieFont(AerieFont.code(12))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // A borderless `Menu` on macOS draws its label with the system control
        // text colour and ignores the label's own `.foregroundStyle`, so in
        // this force-dark window the login rendered near-black. `.tint` is the
        // knob the borderless menu actually reads for its label colour.
        .tint(color)
        .fixedSize()
    }

    private var removeButton: some View {
        RemoveButton(action: onRemove)
    }

    /// Collapses a local path starting with the user's home directory
    /// to a `~/...` form, otherwise returns the path as-is.
    private func collapsedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + String(path.dropFirst(home.count))
    }
}

/// Plain `×` (no chip) per `settings.jsx` line 300 — text-4 at rest,
/// brightening to text-2 on hover.
private struct RemoveButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hover ? AerieColor.text2 : AerieColor.text4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}
