group "default" {
  targets = ["apparat-blueprint"]
}

target "apparat-blueprint" {
  context    = "."
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64", "linux/arm64"]

  labels = {
    "org.opencontainers.image.url" = "https://github.com/potibm/apparat-blueprint"
    "org.opencontainers.image.source" = "https://github.com/potibm/apparat-blueprint"
    "org.opencontainers.image.documentation" = "https://github.com/potibm/apparat-blueprint/tree/main/doc"
    "org.opencontainers.image.authors" = "potibm"
  }
  
  annotations = [
    "index,manifest:org.opencontainers.image.title=Apparat Blueprint",
    "index,manifest:org.opencontainers.image.description=Go/Gin/SQLite backend with a React/Tailwind admin UI.",
    "index,manifest:org.opencontainers.image.url=https://github.com/potibm/apparat-blueprint",
    "index,manifest:org.opencontainers.image.source=https://github.com/potibm/apparat-blueprint",
    "index,manifest:org.opencontainers.image.documentation=https://github.com/potibm/apparat-blueprint/tree/main/doc",
    "index,manifest:org.opencontainers.image.licenses=MIT",
    "index,manifest:org.opencontainers.image.authors=potibm"
  ]
}
