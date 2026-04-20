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

  # Helm-pack single-select enum: category → user's skin key choice (empty = catalog default).
  helm_skin_enum_map = {
    "enterprise_rag"     = var.skin_enterprise_rag
    "enterprise_rag_aiq" = var.skin_enterprise_rag_aiq
  }

  # For Helm packs, resolve the user's enum choice to a catalog entry.
  # Empty selection OR selection not matching any catalog key → catalog default.
  # Non-Helm packs → null.
  helm_pack_selected_skin = (
    contains(keys(local.helm_skin_enum_map), var.starter_pack_category)
    ? try(
      [for s in local.category_skins : s if s.key == local.helm_skin_enum_map[var.starter_pack_category]][0],
      local._catalog_default_skin
    )
    : null
  )

  # Skins the user has enabled/selected for the current category, in catalog order.
  # Blueprint packs: filter by boolean var. Helm packs: singleton with user's enum choice.
  enabled_frontend_skins = (
    local.helm_pack_selected_skin != null
    ? [local.helm_pack_selected_skin]
    : [
      for skin in local.category_skins : skin
      if try(skin.variable_name, "") != ""
      && lookup(local.skin_enabled_map, try(skin.variable_name, ""), false)
    ]
  )

  # First enabled skin. For blueprint packs, non-null when deploy_application=true
  # (precondition guarantees ≥1). For Helm packs, always the user-selected entry
  # (defaulting to catalog default when unset).
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
