terraform {
  required_providers {
    honeycombio = {
      source  = "honeycombio/honeycombio"
      version = "~> 0.49.0"
    }
  }
}

provider "honeycombio" {}
