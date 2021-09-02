use Mix.Config
# For production, don't forget to configure the url host
# to something meaningful, Phoenix uses this information
# when generating URLs.
#
# Note we also include the path to a cache manifest
# containing the digested version of static files. This
# manifest is generated by the `mix phx.digest` task,
# which you should run after static files are built and
# before starting your production server.
config :level10, Level10Web.Endpoint,
  url: [host: "level10.games", port: 443, scheme: "https"],
  cache_static_manifest: "priv/static/cache_manifest.json"

# Do not print debug messages in production
# config :logger, level: :info

# Configure clustering
config :level10,
  cluster_topologies: [
    level10: [
      strategy: Cluster.Strategy.Kubernetes,
      config: [
        kubernetes_ip_lookup_mode: :pods,
        kubernetes_namespace: "default",
        kubernetes_node_basename: "level10",
        kubernetes_selector: "app=level10"
      ]
    ]
  ]
