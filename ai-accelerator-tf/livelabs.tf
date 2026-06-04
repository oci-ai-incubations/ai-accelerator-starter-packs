# =============================================================================
# LiveLabs input interface
# =============================================================================
# LiveLabs (Oracle's developer-workshop platform) injects a fixed set of
# variable names and pre-creates the VCN + a public and a private subnet. This
# file declares those variables and maps them onto the module's internal inputs
# via precedence locals: when a LiveLabs value is supplied it wins; otherwise we
# fall back to the module's native variables (so the ORM console / green-button
# path keeps working unchanged).
#
# Subnet mapping (per workshop design):
#   - public subnet  -> Kubernetes API endpoint + ingress load balancer
#   - private subnet -> worker nodes + 26ai Autonomous DB private endpoint
#
# Authentication is principal-based when LiveLabs inputs are supplied. OCI
# Resource Manager uses Resource Principal; set principal_auth_mode to
# InstancePrincipal only when Terraform runs directly on an OCI compute instance.
# =============================================================================

variable "ociTenancyOcid" {
  type        = string
  default     = ""
  description = "LiveLabs: tenancy OCID. Maps to tenancy_ocid."
}

variable "ociUserOcid" {
  type        = string
  default     = ""
  description = "LiveLabs: user OCID. Maps to current_user_ocid (only used when use_instance_principal=false)."
}

variable "ociCompartmentOcid" {
  type        = string
  default     = ""
  description = "LiveLabs: compartment OCID where all resources are created. Maps to compartment_ocid."
}

variable "ociUserPassword" {
  type        = string
  default     = ""
  sensitive   = true
  description = "LiveLabs: sandbox user password. Used as the default OCI AI Blueprints (corrino) admin password when corrino_admin_password is not set."
}

variable "ociRegionIdentifier" {
  type        = string
  default     = ""
  description = "LiveLabs: region identifier (e.g. us-ashburn-1). Maps to region."
}

variable "resId" {
  type        = string
  default     = ""
  description = "LiveLabs: unique sandbox id, used to make per-sandbox resource names unique."
}

variable "ociPrivateSubnetOcid" {
  type        = string
  default     = ""
  description = "LiveLabs: existing private subnet OCID. Used for worker nodes and the 26ai DB private endpoint."
}

variable "ociPublicSubnetOcid" {
  type        = string
  default     = ""
  description = "LiveLabs: existing public subnet OCID. Used for the Kubernetes API endpoint and ingress load balancer."
}

variable "ociVcnOcid" {
  type        = string
  default     = ""
  description = "LiveLabs: existing VCN OCID. When set, the stack runs in bring-your-own-network mode."
}

locals {
  # --- LiveLabs detection -----------------------------------------------------
  # A LiveLabs VCN being supplied forces bring-your-own-network mode.
  livelabs_mode = var.ociVcnOcid != ""

  # LiveLabs/ORM-style deployments should use principal auth without API keys.
  # principal_auth_mode selects ResourcePrincipal (default for OCI Resource
  # Manager) or InstancePrincipal (OCI compute-hosted Terraform).
  use_instance_principal = local.livelabs_mode ? true : var.use_instance_principal

  # Auth-service (and its backing 26ai DB) is MANDATORY for this workshop pack —
  # hard-coded on. It is not a toggle: the cuopt frontend login page and the
  # cuopt backend both require it, so there is no supported "auth off" mode here.
  # var.enable_auth_service is intentionally ignored (and the schema hides it) so
  # it cannot be turned off or fall back to a disabled state.
  enable_auth_service = true

  # --- Identity precedence ----------------------------------------------------
  tenancy_ocid      = var.ociTenancyOcid != "" ? var.ociTenancyOcid : var.tenancy_ocid
  compartment_ocid  = var.ociCompartmentOcid != "" ? var.ociCompartmentOcid : var.compartment_ocid
  region            = var.ociRegionIdentifier != "" ? var.ociRegionIdentifier : var.region
  current_user_ocid = var.ociUserOcid != "" ? var.ociUserOcid : var.current_user_ocid
  res_id            = var.resId != "" ? var.resId : random_string.deploy_id.result

  # --- Network precedence -----------------------------------------------------
  network_configuration_mode = local.livelabs_mode ? "bring_your_own" : var.network_configuration_mode

  # VCN + subnet OCIDs. Public subnet -> endpoint + LB; private subnet -> nodes + ADB.
  existing_vcn_id_eff = local.livelabs_mode ? var.ociVcnOcid : var.existing_vcn_id
  endpoint_subnet_eff = local.livelabs_mode ? var.ociPublicSubnetOcid : var.existing_endpoint_subnet_id
  lb_subnet_eff       = local.livelabs_mode ? var.ociPublicSubnetOcid : var.existing_lb_subnet_id
  node_subnet_eff     = local.livelabs_mode ? var.ociPrivateSubnetOcid : var.existing_node_subnet_id
  adb_subnet_eff      = local.livelabs_mode ? var.ociPrivateSubnetOcid : var.existing_autonomous_db_subnet_id

  # --- Credential precedence --------------------------------------------------
  # 26ai admin password: explicit var wins, else auto-generated (LiveLabs).
  db_password = coalesce(var.db_password, random_password.livelabs_db_password.result)

  # OCI AI Blueprints (corrino) admin password: explicit var wins, else the
  # LiveLabs sandbox password, else an auto-generated value. Exposed via the
  # corrino_admin_password output so the workshop user can retrieve it.
  corrino_admin_password = (
    var.corrino_admin_password != "" ? var.corrino_admin_password :
    var.ociUserPassword != "" ? var.ociUserPassword :
    random_password.livelabs_corrino_password.result
  )
}

# Auto-generated 26ai admin password. Satisfies both the var.db_password
# validation (>=12 chars, 1 uppercase, 1 special) and Autonomous Database rules
# (12-30 chars; upper/lower/number; no double-quote). override_special avoids
# characters Autonomous DB rejects.
resource "random_password" "livelabs_db_password" {
  length           = 16
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "_#-"
}

# Auto-generated fallback for the corrino admin password.
resource "random_password" "livelabs_corrino_password" {
  length           = 16
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "_#-"
}
