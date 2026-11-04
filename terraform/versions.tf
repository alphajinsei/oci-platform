terraform {
  # oci backend は 1.12 から
  required_version = ">= 1.12"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.11"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.28"
    }
  }

  # state は OCI Object Storage（バケットは Step 0 で CLI から作った）
  backend "oci" {
    bucket    = "tfstate"
    namespace = "nrliaoyraehn"
    key       = "oci-platform/terraform.tfstate"
    region    = "ap-tokyo-1"
  }
}

provider "oci" {
  # 認証は ~/.oci/config の DEFAULT プロファイルから読む
  region = var.region
}

# provider "cloudflare" は cloudflare.tf
