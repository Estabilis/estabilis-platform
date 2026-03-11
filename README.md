# Estabilis Platform

Internal Developer Platform that provisions and manages Kubernetes clusters with a complete observability, security, and GitOps stack.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`)
- [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.5)
- [just](https://github.com/casey/just) (command runner)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)

## Quickstart

```bash
# 1. Clone the repository
git clone https://github.com/org-estabilis/estabilis-platform.git
cd estabilis-platform

# 2. Setup git hooks
just setup-hooks

# 3. Configure secrets
cp bootstrap/secrets.env.example bootstrap/secrets.env
# Edit bootstrap/secrets.env with your Azure credentials and settings

# 4. Bootstrap the platform
just bootstrap domain=your-domain.com

# 5. Verify everything is running
just verify
```

## Architecture

See [CLAUDE.md](./CLAUDE.md) for detailed architecture documentation, component descriptions, and design decisions.

## License

This project is licensed under the [Elastic License 2.0](./LICENSE).
