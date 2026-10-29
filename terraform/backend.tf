terraform {
  backend "s3" {
    key          = "kube-news/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
