# Frontend Skins — resolves user's skin selection to an image URI.
# Reads from schemas/frontend_skins.yaml (same file used by create_final_schema.py).

locals {
  # Read the shared skin catalog
  frontend_skins_catalog = yamldecode(file("${path.module}/schemas/frontend_skins.yaml"))

  # Get skins for the current category
  category_skins = local.frontend_skins_catalog[var.starter_pack_category]["skins"]

  # Resolve effective skin: use the user's selection, or fall back to the
  # catalog default when running locally without ORM (var.frontend_skin == "")
  effective_frontend_skin = coalesce(
    var.frontend_skin,
    local.frontend_skins_catalog[var.starter_pack_category]["default"]
  )

  # Resolve the effective skin to the matching catalog entry
  selected_skin = [
    for skin in local.category_skins : skin
    if skin.key == local.effective_frontend_skin
  ][0]

  # The values consumers need
  frontend_skin_image_uri      = local.selected_skin.image_uri
  frontend_skin_provider       = local.selected_skin.provider
  frontend_skin_name           = local.selected_skin.key
  frontend_skin_container_port = local.selected_skin.container_port
  frontend_skin_inject_env     = local.selected_skin.inject_env
}
