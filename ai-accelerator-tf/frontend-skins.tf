# Frontend Skins — resolves enabled skins and exposes helper locals.
# Reads the shared catalog at schemas/frontend_skins.yaml.

locals {
  frontend_skins_catalog = yamldecode(file("${path.module}/schemas/frontend_skins.yaml"))
  category_skins         = local.frontend_skins_catalog[var.starter_pack_category]["skins"]

  # Map of skin variable_name → var value. Must stay in sync with vars.tf.
  # Referencing an undeclared var is a plan-time error, which catches mismatches.
  skin_enabled_map = {
    "skin_cuopt_core"    = var.skin_cuopt_core
    "skin_cuopt_partner" = var.skin_cuopt_partner
    "skin_vss_core"      = var.skin_vss_core
    "skin_paas_rag_core" = var.skin_paas_rag_core
  }

  # Skins the user has enabled for the current category, in catalog order.
  # Empty for Helm packs (their catalog entries have no variable_name).
  enabled_frontend_skins = [
    for skin in local.category_skins : skin
    if try(skin.variable_name, "") != ""
    && lookup(local.skin_enabled_map, skin.variable_name, false)
  ]

  # Primary skin for blueprint packs. null for Helm packs (no multi-skin concept).
  # The precondition ensures blueprint packs always have ≥1 skin when deploy_application=true,
  # so primary_skin is non-null in that case.
  primary_skin = length(local.enabled_frontend_skins) > 0 ? local.enabled_frontend_skins[0] : null

  # Catalog's default skin entry, derived from the top-level default: key.
  # Used by (a) the VSS K8s naming rule (default keeps base name) and
  # (b) back-compat locals below (Helm-pack fallback).
  _catalog_default_skin = try(
    [
      for skin in local.category_skins : skin
      if skin.key == local.frontend_skins_catalog[var.starter_pack_category].default
    ][0],
    null
  )

  # Fail-fast assertion: every known category must have a resolvable catalog default.
  # If the catalog's top-level default: key fails to match any skin.key, _catalog_default_skin
  # is null — which would silently break the VSS K8s naming rule (every skin becomes non-default
  # and takes a suffix, breaking the upgrade-without-rename promise). Catch this early.
  _assert_catalog_default_resolves = local._catalog_default_skin != null ? true : tobool("catalog default for ${var.starter_pack_category} did not match any skin key")

  default_skin_variable_name = try(local._catalog_default_skin.variable_name, null)

  # Back-compat locals used by helm.tf split(":", image_uri), VSS locals, and outputs.
  # Blueprint packs: return primary_skin's values.
  # Helm packs: fall back to the catalog's default skin entry (always has image_uri/
  # provider/key/container_port, though not subdomain/variable_name).
  frontend_skin_image_uri = (
    local.primary_skin != null
    ? local.primary_skin.image_uri
    : try(local._catalog_default_skin.image_uri, null)
  )
  frontend_skin_provider = (
    local.primary_skin != null
    ? local.primary_skin.provider
    : try(local._catalog_default_skin.provider, null)
  )
  frontend_skin_name = (
    local.primary_skin != null
    ? local.primary_skin.key
    : try(local._catalog_default_skin.key, null)
  )
  frontend_skin_container_port = (
    local.primary_skin != null
    ? local.primary_skin.container_port
    : try(local._catalog_default_skin.container_port, null)
  )
}
