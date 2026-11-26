# Git Multi-Account SSH & PowerShell Execution Guide

A quick-reference guide covering multi-account SSH configuration for Git, one-time SSH key overrides, and PowerShell script execution policies.

---

## 1. Multi-Account SSH Configuration (`~/.ssh/config`)

Git hosts like GitHub identify your account strictly by **which SSH public key you authenticate with**, not by your email address or username. Keep `User git` on every entry and use distinct `Host` aliases to separate accounts.

### Example `~/.ssh/config`

```sshconfig
# Primary / Personal GitHub Account
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

# Secondary / Work GitHub Account
Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes
```

> **Note:** `IdentitiesOnly yes` prevents `ssh-agent` from offering cached keys that aren't explicitly specified in the matched `Host` block.

### Updating Repository Remotes & Testing

* **Point a repo to the secondary account:**
  ```bash
  git remote set-url origin git@github-work:username-or-org/repo-name.git
  ```
* **Verify which account each alias authenticates as:**
  ```bash
  ssh -T git@github.com
  ssh -T git@github-work
  ```
* **Check and clear cached keys in `ssh-agent` (if an old key keeps getting picked):**
  ```bash
  ssh-add -l                          # List loaded keys
  ssh-add -d ~/.ssh/id_ed25519_old    # Remove a specific key
  ssh-add -D                          # Remove all loaded keys
  ```

---

## 2. One-Time SSH Identity File Override

When you want to use a specific SSH key for a single command without modifying `~/.ssh/config` or adding keys to `ssh-agent`:

### For Standard SSH
```bash
ssh -i ~/.ssh/id_ed25519_custom -o IdentitiesOnly=yes -T git@github.com
```

### For Git Commands (Clone, Pull, Push, Fetch)

**Linux / macOS (Bash/Zsh) — inline environment variable:**
```bash
GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519_custom -o IdentitiesOnly=yes" git clone git@github.com:org/repo.git
```

**Windows (PowerShell) — inline config flag (`-c`):**
```powershell
git -c core.sshCommand="ssh -i ~/.ssh/id_ed25519_custom -o IdentitiesOnly=yes" clone git@github.com:org/repo.git
```

*(Note: `git -c core.sshCommand="..."` works cross-platform in Bash, Zsh, CMD, and PowerShell.)*

---

## 3. Allowing PowerShell Script Execution

PowerShell restricts script execution by default on Windows clients (`Restricted`). Use the commands below depending on whether you need a one-time bypass, a current-user change, or a system-wide setting.

### Check Current Execution Policies
```powershell
Get-ExecutionPolicy -List
```

### Option A: Current User Only (Recommended — No Admin Required)
Allows local scripts you write to run, while requiring remote/downloaded scripts to be signed:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Option B: Single Session Only (Temporary)
Applies only to the currently open PowerShell terminal window and resets when closed:
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

### Option C: One-Time Script Execution (Without Changing Policy)
Run a single `.ps1` file directly from CMD or PowerShell without altering any saved policy:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\your-script.ps1"
```

### Option D: Local Machine / All Users (Requires Administrator)
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
```

### Unblocking a Downloaded Script
If `RemoteSigned` blocks a script downloaded from the internet, unblock that specific file rather than lowering your execution policy to `Unrestricted`:
```powershell
Unblock-File -Path ".\downloaded-script.ps1"
```

### Execution Policy Reference

| Policy | Behavior |
| :--- | :--- |
| **`Restricted`** | Default on Windows clients; blocks all `.ps1` script files. |
| **`RemoteSigned`** | Runs local scripts; requires scripts downloaded from the internet to have a trusted digital signature. |
| **`Unrestricted`** | Runs all scripts (warns before running downloaded scripts). |
| **`Bypass`** | Nothing is blocked and no warnings or prompts are shown (ideal for automation/one-off runs). |
| **`AllSigned`** | All scripts—including local ones—must be signed by a trusted publisher. |