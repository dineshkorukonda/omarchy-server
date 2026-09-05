defmodule SSHClientWeb.HostLiveTest do
  use ExUnit.Case, async: true

  alias SSHClientWeb.HostLive

  test "initial_state returns standard map structure" do
    state = HostLive.initial_state()
    assert is_list(state.servers)
    assert state.filter == ""
    assert state.add_server_modal == false
  end

  test "format_server formats server map and assigns status badge color" do
    server = %{
      id: "prod-1",
      name: "Production Web",
      host: "192.168.1.100",
      status: :polling,
      metrics: %{cpu_percent: 15.5, ram_percent: 42.0, disk_percent: 60.0},
      checks: %{nginx: :running}
    }

    formatted = HostLive.format_server(server)
    assert formatted.id == "prod-1"
    assert formatted.name == "Production Web"
    assert formatted.host == "192.168.1.100"
    assert formatted.status == "polling"
    assert formatted.status_badge_color =~ "emerald"
    assert formatted.cpu_percent == 15.5
    assert formatted.ram_percent == 42.0
  end

  test "filter_servers filters by query string" do
    servers = [
      %{id: "srv-1", name: "Web Alpha", host: "10.0.0.1"},
      %{id: "srv-2", name: "DB Master", host: "10.0.0.2"}
    ]

    assert length(HostLive.filter_servers(servers, "")) == 2
    assert length(HostLive.filter_servers(servers, "alpha")) == 1
    assert hd(HostLive.filter_servers(servers, "alpha")).id == "srv-1"
    assert length(HostLive.filter_servers(servers, "10.0.0.2")) == 1
  end

  test "render_html returns HTML string with table and rows" do
    servers = [
      HostLive.format_server(%{id: "s1", name: "Alpha", host: "example.com", status: :polling})
    ]

    html = HostLive.render_html(%{servers: servers, filter: ""})
    assert is_binary(html)
    assert html =~ "Hosts &amp; Status" or html =~ "Hosts & Status"
    assert html =~ "Alpha"
    assert html =~ "example.com"
  end
end
