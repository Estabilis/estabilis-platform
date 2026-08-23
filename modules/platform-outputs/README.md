# platform-outputs

Writes what Terraform knows about the infrastructure into the cluster, where
ArgoCD reads it: the `argocd` namespace, the `platform-infrastructure` ConfigMap
and its sensitive Secret, the `hub-cluster` Secret, and ArgoCD's repository
credential.

## Why this is a module and not part of a provider

It was part of `providers/digitalocean`, and that was wrong for a reason worth
recording.

Everything else a provider does talks to a cloud API. This talks to the
**Kubernetes API**, and on DigitalOcean that endpoint sits behind a control
plane firewall that allows a list of addresses. A hosted CI runner draws from a
shared pool and is not on it — so the moment these resources joined the
foundation's state, every plan of the foundation needed cluster access, and the
pipeline that had been applying it stopped working:

```
Error: Get "https://<cluster>.k8s.ondigitalocean.com/api/v1/namespaces/argocd":
       dial tcp: i/o timeout
```

Separating it is not tidiness. It keeps the foundation applicable by CI while
the handoff waits for whatever can reach the cluster — a workstation today, an
in-cluster runner once ArgoCD is up.

## Inputs are values, not resources

Every input is a plain value, so the caller decides where they come from: a
sibling module, a `terraform_remote_state` of the foundation, or literals. That
is what lets this live in a different root module, and a different state, from
the infrastructure it describes.
