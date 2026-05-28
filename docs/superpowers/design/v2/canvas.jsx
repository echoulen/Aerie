// Top-level canvas — all artboards assembled here so each section
// (app, settings, dialogs, add-repo, icon) lives in its own file.

function App() {
  return (
    <DesignCanvas>
      <DCSection
        id="aerie"
        title="Aerie"
        subtitle="Two views. Dark glass. Maximum whitespace. Single amber accent — used only when something is ready for you."
      >
        <DCArtboard id="prs" label="Pull Requests" width={W} height={H} bg="transparent" framed={false}>
          <Window><PRView /></Window>
        </DCArtboard>
        <DCArtboard id="repos" label="Repositories" width={W} height={H} bg="transparent" framed={false}>
          <Window><RepoView /></Window>
        </DCArtboard>
      </DCSection>

      <DCSection
        id="settings"
        title="Settings"
        subtitle="Local gh accounts + tracked repositories. Same glass shell, sidebar with two sections."
      >
        <DCArtboard id="settings-accounts"     label="Settings · Accounts"     width={SET_W} height={SET_H} bg="transparent" framed={false}>
          <SettingsAccounts />
        </DCArtboard>
        <DCArtboard id="settings-repositories" label="Settings · Repositories" width={SET_W} height={SET_H} bg="transparent" framed={false}>
          <SettingsRepositories />
        </DCArtboard>
      </DCSection>

      <DCSection
        id="add-repo"
        title="Add repository"
        subtitle="Sheet attached to the Settings · Repositories window. Two states: detected (with origin URL parsed) and empty (waiting for a folder)."
      >
        <DCArtboard id="addrepo-detected" label="Add repo · detected" width={SET_W} height={SET_H} bg="transparent" framed={false}>
          <AddRepoSheet state="detected" />
        </DCArtboard>
        <DCArtboard id="addrepo-empty"    label="Add repo · empty"    width={SET_W} height={SET_H} bg="transparent" framed={false}>
          <AddRepoSheet state="empty" />
        </DCArtboard>
      </DCSection>

      <DCSection
        id="dialogs"
        title="Confirmation dialogs"
        subtitle="Reset is destructive · Merge is the only amber action · Sign out and Remove are softer because they don't touch your files."
      >
        <DCArtboard id="dlg-reset"   label="Reset · hard reset to origin/main" width={W} height={H} bg="transparent" framed={false}>
          <DialogReset />
        </DCArtboard>
        <DCArtboard id="dlg-merge"   label="Merge · PR #142"                   width={W} height={H} bg="transparent" framed={false}>
          <DialogMerge />
        </DCArtboard>
        <DCArtboard id="dlg-signout" label="Sign out · cli-work"               width={W} height={H} bg="transparent" framed={false}>
          <DialogSignOut />
        </DCArtboard>
        <DCArtboard id="dlg-remove"  label="Remove · sketchpad"                width={W} height={H} bg="transparent" framed={false}>
          <DialogRemoveRepo />
        </DCArtboard>
      </DCSection>

      <DCSection
        id="mcp"
        title="MCP — Model Context Protocol"
        subtitle="Consent dialog on first launch · live activity toasts when an agent writes · full Settings panel for status, integration and audit log."
      >
        <DCArtboard id="mcp-consent"   label="MCP · consent dialog (first launch)" width={W} height={H} bg="transparent" framed={false}>
          <DialogMCPConsent />
        </DCArtboard>
        <DCArtboard id="mcp-toast"     label="MCP · activity toasts" width={W} height={H} bg="transparent" framed={false}>
          <ToastStack />
        </DCArtboard>
        <DCArtboard id="mcp-settings"  label="Settings · MCP" width={SET_W} height={SET_H} bg="transparent" framed={false}>
          <SettingsMCP />
        </DCArtboard>
      </DCSection>

      <DCSection
        id="first-run"
        title="First-run gh setup"
        subtitle="Blocking onboarding when gh is missing or unauthenticated. Warm tone, single big action."
      >
        <DCArtboard id="first-run-no-gh"   label="gh not installed"        width={W} height={H} bg="transparent" framed={false}>
          <FirstRun state="no-gh" />
        </DCArtboard>
        <DCArtboard id="first-run-no-auth" label="gh installed · no auth"  width={W} height={H} bg="transparent" framed={false}>
          <FirstRun state="no-auth" />
        </DCArtboard>
      </DCSection>

      <DCSection
        id="advanced"
        title="Settings · Advanced"
        subtitle="Polling cadence sliders, per-account rate-limit status, behavior toggles."
      >
        <DCArtboard id="settings-advanced" label="Settings · Advanced" width={SET_W} height={SET_H} bg="transparent" framed={false}>
          <SettingsAdvanced />
        </DCArtboard>
      </DCSection>

      <DCSection
        id="icon"
        title="App icon"
        subtitle="Sodium amber radar-orb on dark glass squircle. Designed to read clearly down to 16px."
      >
        <DCArtboard id="icon-showcase" label="Showcase" width={1100} height={760} bg="transparent" framed={false}>
          <div style={{
            width:'100%', height:'100%',
            borderRadius:14, overflow:'hidden',
            border:'1px solid var(--glass-line)',
          }}>
            <AppIconShowcase />
          </div>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
