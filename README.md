# Skills

Claude Code skills for use with `~/.claude/skills/`.

## Skills

- `netgraph-dev` - NetGraph development workflow
- `netgraph-dsl` - NetGraph scenario DSL reference
- `omnigraffle-automation` - OmniGraffle plugin development

## Install

```bash
git clone https://github.com/networmix/skills.git
cd skills
./install.sh --all
```

## Usage

```bash
./install.sh              # Interactive mode
./install.sh --all        # Install all
./install.sh --list       # List skills and status
./install.sh skill1 ...   # Install specific skills
./install.sh --uninstall skill1    # Remove skill
./install.sh --uninstall-all       # Remove all
```

Skills are symlinked into `~/.claude/skills/`.
