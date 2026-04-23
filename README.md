# Estabilis Platform

Internal Developer Platform that provisions and manages Kubernetes clusters with a complete observability, security, and GitOps stack.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`) or [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) depending on the target provider
- [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.7)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- [pre-commit](https://pre-commit.com/#install) (for contributors)

## Development setup

Before making changes, install the pre-commit hooks once per clone:

```bash
pip install pre-commit
pre-commit install                           # run on every commit
pre-commit install --hook-type commit-msg    # enforce Conventional Commits
```

The hooks cover: `terraform fmt`, `terraform validate`, `tflint`, secret scanning (`detect-private-key`, `detect-aws-credentials`, `gitleaks`), YAML syntax, line-ending normalization, large-file protection, and Conventional Commits on `commit-msg`. Run the full suite anytime:

```bash
pre-commit run --all-files
```

On first run the terraform and tflint hooks download their dependencies (providers + tflint plugins); subsequent runs are near-instant.

## Quickstart

```bash
# 1. Clone the repository
git clone https://github.com/Estabilis/estabilis-platform.git
cd estabilis-platform

# 2. Install pre-commit hooks (see Development setup above)

# 3. Configure tfvars + secrets in your downstream repo (estabilis-platform-downstream)

# 4. From the downstream, run terraform against the target provider
cd providers/azure  # or providers/aws
terraform init
terraform plan  -var-file=<provider>.tfvars
terraform apply -var-file=<provider>.tfvars
```

## Architecture

See [CLAUDE.md](./CLAUDE.md) for detailed architecture documentation, component descriptions, and design decisions.

## License

This project is licensed under the [Elastic License 2.0](./LICENSE).
