defmodule SSHClient.Updater do
  @moduledoc """
  Checks for application updates from the GitHub repository release endpoint.
  Provides information about latest available releases, download URLs, and changelog.
  """

  @current_version "0.0.1"
  @repo_owner "dineshkorukonda"
  @repo_name "ssh-client"
  @api_url "https://api.github.com/repos/#{@repo_owner}/#{@repo_name}/releases/latest"

  @doc """
  Returns the current running version of the application.
  """
  def current_version, do: @current_version

  @doc """
  Checks GitHub Releases for the latest version.
  Returns `{:ok, info}` or `{:error, reason}`.
  """
  def check_update(opts \\ []) do
    api_url = Keyword.get(opts, :api_url, @api_url)
    timeout = Keyword.get(opts, :timeout, 5000)

    # Ensure inets and ssl are started
    :inets.start()
    :ssl.start()

    headers = [
      {~c"User-Agent", ~c"ssh-client/#{@current_version}"},
      {~c"Accept", ~c"application/vnd.github.v3+json"}
    ]

    http_opts = [
      timeout: timeout,
      connect_timeout: timeout,
      ssl: [verify: :verify_none]
    ]

    case :httpc.request(:get, {String.to_charlist(api_url), headers}, http_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _resp_headers, body}} ->
        case :json.decode(body) do
          %{} = data ->
            latest_tag = Map.get(data, "tag_name", "v#{@current_version}")
            latest_version = String.trim_leading(latest_tag, "v")
            html_url = Map.get(data, "html_url", "https://github.com/#{@repo_owner}/#{@repo_name}/releases")
            published_at = Map.get(data, "published_at")
            body_notes = Map.get(data, "body", "")

            assets =
              data
              |> Map.get("assets", [])
              |> Enum.map(fn asset ->
                %{
                  name: Map.get(asset, "name"),
                  browser_download_url: Map.get(asset, "browser_download_url"),
                  size: Map.get(asset, "size", 0)
                }
              end)

            update_available? = version_greater?(latest_version, @current_version)

            {:ok,
             %{
               current_version: @current_version,
               latest_version: latest_version,
               tag_name: latest_tag,
               update_available?: update_available?,
               release_url: html_url,
               notes: body_notes,
               published_at: published_at,
               assets: assets
             }}

          _ ->
            {:error, "Failed to parse release response"}
        end

      {:ok, {{_, 404, _}, _, _}} ->
        {:ok,
         %{
           current_version: @current_version,
           latest_version: @current_version,
           tag_name: "v#{@current_version}",
           update_available?: false,
           release_url: "https://github.com/#{@repo_owner}/#{@repo_name}/releases",
           notes: "No releases found.",
           published_at: nil,
           assets: []
         }}

      {:ok, {{_, status, status_str}, _, _}} ->
        {:error, "GitHub API returned HTTP #{status} (#{to_string(status_str)})"}

      {:error, reason} ->
        {:error, "Network request failed: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Compares two semantic version strings (e.g. "0.0.2" > "0.0.1").
  """
  def version_greater?(v1, v2) do
    case {Version.parse(v1), Version.parse(v2)} do
      {{:ok, ver1}, {:ok, ver2}} ->
        Version.compare(ver1, ver2) == :gt

      _ ->
        # Fallback string comparison
        v1 > v2
    end
  end
end
