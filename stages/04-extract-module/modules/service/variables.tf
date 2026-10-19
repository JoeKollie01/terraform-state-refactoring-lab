variable "name" {
  description = "Service name, e.g. auth"
  type        = string
}

variable "cluster_name" {
  description = "Cluster the service runs on"
  type        = string
}

variable "output_dir" {
  description = "Folder the service manifest is written to"
  type        = string
}
