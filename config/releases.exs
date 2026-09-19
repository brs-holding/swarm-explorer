# In this file, we load production configuration and secrets
# from environment variables.
import Config

secret_key_base =
  System.fetch_env!("SECRET_KEY_BASE") ||
    raise """
    environment variable SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """

zcashd_hostname =
  System.fetch_env!("ZCASHD_HOSTNAME") ||
    raise """
    environment variable ZCASHD_HOSTNAME is missing
    """

zcashd_port =
  System.fetch_env!("ZCASHD_PORT") ||
    raise """
    environment variable ZCASHD_PORT is missing
    """

zcashd_username =
  System.fetch_env!("ZCASHD_USERNAME") ||
    raise """
    environment variable ZCASHD_USERNAME is missing
    """

zcashd_password =
  System.fetch_env!("ZCASHD_PASSWORD") ||
    raise """
    environment variable ZCASHD_PASSWORD is missing
    """

# initializes the Zcashd Onion Address for Tor connectivity from onion_addres file content.

be_onion_address =
  case File.read("onion_address.txt") do
    {:ok, content} -> content
    {:error, _reason} -> System.get_env("BE_ONION_ADDRESS") || ""
  end

explorer_hostname =
  System.fetch_env!("EXPLORER_HOSTNAME") ||
    raise """
    environment variable EXPLORER_HOSTNAME is missing
    """

vk_cpus =
  System.fetch_env!("VK_CPUS") ||
    raise """
    environment variable VK_CPUS is missing
    """

vk_mem =
  System.fetch_env!("VK_MEM") ||
    raise """
    environment variable VK_MEM is missing
    """

vk_runnner_image =
  System.fetch_env!("VK_RUNNER_IMAGE") ||
    raise """
    environment variable VK_RUNNER_IMAGE is missing
    """

zcash_network =
  System.fetch_env!("ZCASH_NETWORK") ||
    raise """
    environment variable ZCASH_NETWORK is missing
    """

# :debug here wrote a full stack trace plus every request's params to the
# container log; it reached 7.2 GB with no rotation. Override with LOG_LEVEL.
config :logger, level: String.to_existing_atom(System.get_env("LOG_LEVEL", "info"))

IO.puts("Configuration loaded for #{zcash_network} at #{explorer_hostname}")

config :zcash_explorer, ZcashExplorerWeb.Endpoint,
  url: [
    host: explorer_hostname,
    port: String.to_integer(System.get_env("EXPLORER_PORT") || "443"),
    scheme: System.get_env("EXPLORER_SCHEME") || "https"
  ],
  http: [
    port: String.to_integer(System.get_env("PORT") || "4000"),
    transport_options: [socket_opts: [:inet6], compress: true]
  ],
  secret_key_base: secret_key_base,
  # add all the domain names that will be routed to this application ( including TOR Onion Service)
  check_origin: [
    "http://127.0.0.1:4000",
    "//zcashblockexplorer.com",
    "//testnet.zcashblockexplorer.com",
    "//" <> be_onion_address
  ],
  be_onion_address: be_onion_address

IO.inspect("Setting up Zcashex configuration", label: "Configuration")

config :zcash_explorer, Zcashex,
  zcashd_hostname: zcashd_hostname,
  zcashd_port: zcashd_port,
  zcashd_username: zcashd_username,
  zcashd_password: zcashd_password,
  vk_cpus: vk_cpus,
  vk_mem: vk_mem,
  vk_runnner_image: vk_runnner_image,
  zcash_network: zcash_network

IO.inspect("Setting up Logger configuration", label: "Configuration")
config :zcash_explorer, ZcashExplorerWeb.Endpoint, server: true
IO.inspect("configuration complete", label: "Configuration")
