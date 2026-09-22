defmodule ZcashExplorerWeb.ErrorView do
  use ZcashExplorerWeb, :view

  # If you want to customize a particular status code
  # for a certain format, you may uncomment below.
  # def render("500.html", _assigns) do
  #   "Internal Server Error"
  # end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def template_not_found(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end

  # SWARM change: `render("invalid_input.html", _)` returned the string
  # "Invalid input" from here. It is a real page now — templates/error/ — so
  # that a search which matches nothing, an address the node does not know and
  # a block that does not exist all say what this explorer can look up. Every
  # caller passes a `:query` assign, which the template echoes back.
  def render("404.html", _assigns) do
    "Not Found"
  end
end
