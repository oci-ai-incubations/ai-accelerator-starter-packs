# Frontend Skins — resolves enabled skins and exposes helper locals.
# Reads the shared catalog at schemas/frontend_skins.yaml.

locals {
  frontend_skins_catalog = yamldecode(file("${path.module}/schemas/frontend_skins.yaml"))
  category_skins         = local.frontend_skins_catalog[var.starter_pack_category]["skins"]

  # Map of skin variable_name → var value. Must stay in sync with vars.tf.
  # Referencing an undeclared var is a plan-time error, which catches mismatches.
  # cuOpt-only build: just the two cuopt skins.
  skin_enabled_map = {
    "skin_cuopt_core"    = var.skin_cuopt_core
    "skin_cuopt_partner" = var.skin_cuopt_partner
  }

  # Skins the user has enabled for cuOpt, in catalog order (filter by boolean var).
  enabled_frontend_skins = [
    for skin in local.category_skins : skin
    if try(skin.variable_name, "") != ""
    && lookup(local.skin_enabled_map, try(skin.variable_name, ""), false)
  ]

  # First enabled skin. Non-null when deploy_application=true (the skin-validation
  # precondition guarantees ≥1 enabled skin).
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

  # Catalog-default correctness (the top-level `default:` key must match some skin.key)
  # is enforced by pytest: test_default_enabled_matches_top_level_default covers blueprint
  # packs, test_helm_packs_expose_single_skin_enum covers Helm packs. We intentionally
  # don't carry a plan-time `tobool(...)` assertion here; pytest coverage fires earlier
  # in CI. The local below is kept for future schema-introspection consumers.
  # tflint-ignore: terraform_unused_declarations
  default_skin_variable_name = try(local._catalog_default_skin.variable_name, null)

  # Back-compat locals used by helm.tf split(":", image_uri), VSS locals, and outputs.
  # Blueprint packs: return primary_skin's values.
  # Helm packs: fall back to the catalog's default skin entry.
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
}
