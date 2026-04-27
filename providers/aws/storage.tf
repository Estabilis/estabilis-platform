# ---------------------------------------------------------------------------
# Default StorageClass — gp3
#
# Every Estabilis AWS cluster needs at least one StorageClass marked as
# default-class. Without one, every PVC that omits `storageClassName`
# (loki, mimir, vault, cnpg, tempo, pyroscope, ...) stays Pending.
#
# EKS 1.30+ does NOT auto-create the legacy in-tree gp2 StorageClass,
# so the cluster-side declaration here is mandatory. The aws-ebs-csi-
# driver addon is installed by eks.tf and provides the
# `ebs.csi.aws.com` provisioner this class consumes.
#
# Knobs intentionally exposed:
#   - default flag        — operator can opt-out for clusters that bring
#                           their own default class.
#   - allowVolumeExpansion=true — gp3 supports online expansion; setting
#                           this on the SC lets `kubectl edit pvc` resize
#                           without recreating the volume.
#   - encrypted=true      — matches the EC2NodeClass root-disk policy
#                           (every node EBS encrypted via Karpenter
#                           values). Defaults to encrypted at rest;
#                           operator can opt out per-cluster if measured
#                           overhead matters for a specific workload.
#   - throughput / iops   — gp3 charges separately above the baseline
#                           (125 MiB/s, 3000 IOPS). Empty by default →
#                           AWS applies the free-tier baseline.
#
# Upgrade note for clusters that already carry a hand-applied `gp3`
# StorageClass: the first apply after pulling this module will fail
# with `AlreadyExists`. Import once, then apply:
#
#     terraform import \
#       'module.estabilis_platform.kubernetes_storage_class_v1.gp3[0]' gp3
#
# Differences with the hand-applied class (allowVolumeExpansion,
# encrypted) are non-destructive — they only affect new PVCs created
# after the apply, never existing volumes.
# ---------------------------------------------------------------------------

resource "kubernetes_storage_class_v1" "gp3" {
  count = var.create_default_storage_class ? 1 : 0

  metadata {
    name = "gp3"

    annotations = {
      "storageclass.kubernetes.io/is-default-class" = tostring(var.default_storage_class_is_default)
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = merge(
    {
      type      = "gp3"
      encrypted = tostring(var.default_storage_class_encrypted)
    },
    var.default_storage_class_throughput != null ? { throughput = tostring(var.default_storage_class_throughput) } : {},
    var.default_storage_class_iops != null ? { iops = tostring(var.default_storage_class_iops) } : {},
  )

  # The aws-ebs-csi-driver addon is wired inside module.eks (eks.tf
  # cluster_addons), so depending on module.eks alone is enough — the
  # addon is established by the time the module finishes applying.
  depends_on = [module.eks]
}
