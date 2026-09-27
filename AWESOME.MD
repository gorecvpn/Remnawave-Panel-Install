### Remnawave Management Scripts v3.5.5 by DigneZzZ

Comprehensive bash scripts for **Remnawave Panel**, **Remnawave Node**, and **Reality Selfsteal** with full automation support. Features Docker integration, intelligent backup/restore system with version checking, advanced monitoring, and complete lifecycle management.

📦 **Key Features:**
- 🚀 **One-line installation** for Panel, Node, and Selfsteal configurations
- 🎛️ **Interactive menus** with real-time status monitoring and guided operations
- 💾 **Smart backup system** with version compatibility checking and safety rollbacks
- 🔄 **Complete lifecycle management** - install, update, backup, restore, uninstall
- 🎯 **Reality masking** with 11 AI-generated website templates


📦 Full info, updates, and examples: [**/remnawave-scripts**](https://github.com/gorecvpn/Remnawave-Panel-Install)

Author: [DigneZzZ](https://github.com/DigneZzZ)

---

<details>
<summary>🚀 Quick Install Commands</summary>

**Remnawave Panel (v3.5.5+):**
```bash
bash <(curl -Ls https://github.com/gorecvpn/Remnawave-Panel-Install/raw/main/remnawave.sh) @ install
```

**Remnawave Node (v3.1.2+):**
```bash
bash <(curl -Ls https://github.com/gorecvpn/Remnawave-Panel-Install/raw/main/remnanode.sh) @ install
```

**Reality Selfsteal (v2.1.3+):**
```bash
bash <(curl -Ls https://github.com/gorecvpn/Remnawave-Panel-Install/raw/main/selfsteal.sh) @ install
```

**Options:**
- Add `--dev` for development version
- Add `--name customname` for custom directory (default: `/opt/remnawave`, `/opt/remnanode`)

**For existing installations:**
Use `install-script` to add CLI wrapper only:
```bash
bash <(curl -Ls https://github.com/gorecvpn/Remnawave-Panel-Install/raw/main/remnawave.sh) @ install-script
```

</details>

<details>
<summary>⚙️ Available CLI Commands</summary>

**Installation & Management:**
- `install`, `update`, `uninstall`
- `install-script`, `uninstall-script`

**Service Control:**
- `up`, `down`, `restart`, `status`, `logs`

**Node-specific Commands:**
- `core-update` - Update Xray-core to latest version
- `xray-log-out`, `xray-log-err` - View Xray logs
- `setup-logs` - Configure log rotation

**Configuration:**
- `edit`, `edit-env`, `console` (Panel only)

**Interactive Menus:**
- Run `remnawave`, `remnanode`, or `selfsteal` without arguments for interactive menu
- Real-time status monitoring and resource usage
- Step-by-step guided operations

**Backup & Restore (Panel):**
- `backup` - Create manual backup
- `schedule` - Configure automated backups
- `restore` - Restore from backup archive

**Reality Selfsteal:**
- Choose from 11 AI-generated website templates
- Automatic SSL certificate management
- DNS validation and domain setup

Run `remnawave help`, `remnanode help`, or `selfsteal help` for detailed usage.

</details>

<details>
<summary>💾 Intelligent Backup & Restore System</summary>

**🔄 Smart Backup Features:**

- **Version-aware backups** with compatibility checking
- **Safety restore** with automatic rollback protection  
- **Scheduled automation** with cron integration
- **Telegram notifications** with file delivery and alerts
- **Cross-server migration** support
- **Compressed archives** with unified structure

**📦 What's Backed Up:**

- PostgreSQL database as `db_backup.sql`
- Configuration files: `docker-compose.yml`, `.env`, `app-config.json`
- Optional: full directory backup with selective restore

**🎯 Quick Commands:**

```bash
remnawave backup          # Create instant backup
remnawave schedule        # Setup automated backups  
remnawave restore         # Intelligent restore with version checks
```

**🛡️ Safety Features:**

- Automatic version compatibility verification
- Safety backup before restore operations
- Rollback capability if restore fails
- Real-time status monitoring during operations

**📋 Restore Options:**

- Full restore (replace all files and database)
- Database-only restore (keep existing files)
- Custom directory restoration
- Manual restore commands included in each backup archive

**Legacy Standalone Scripts:**

Still available for users who prefer separate backup/restore tools:

- [remnawave-backup.sh](https://github.com/gorecvpn/Remnawave-Panel-Install/raw/main/remnawave-backup.sh) - Standalone backup script
- [restore.sh](https://github.com/gorecvpn/Remnawave-Panel-Install/raw/main/restore.sh) - Standalone restore script

</details>

<div style={{ display: 'flex', justifyContent: 'center', gap: '1rem' }}>
  <Button label="Github repository" link="https://github.com/gorecvpn/Remnawave-Panel-Install" variant="secondary" size="md" outline />
</div>
<br />
<div style={{ display: 'flex', justifyContent: 'center' }}>
  <img src="/awesome/remnawave-script.webp" alt="Remnawave Management Scripts" width="600" />
</div>

---