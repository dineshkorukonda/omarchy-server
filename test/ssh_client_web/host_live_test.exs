defmodule SSHClientWeb.HostLiveTest do
  use ExUnit.Case, async: true

  alias SSHClientWeb.HostLive

  test "filter_servers returns all servers when query is empty" do
    servers = [
      %{id: "srv-1", name: "Production Web Alpha", host: "10.0.0.1"},
      %{id: "srv-2", name: "Database Master", host: "10.0.0.2"},
      %{id: "srv-3", name: "Staging Redis", host: "10.0.0.3"}
    ]

    assert length(HostLive.filter_servers(servers, "")) == 3
  end

  test "filter_servers filters by name substring" do
    servers = [
      %{id: "srv-1", name: "Production Web", host: "10.0.0.1"},
      %{id: "srv-2", name: "Database Master", host: "10.0.0.2"}
    ]

    result = HostLive.filter_servers(servers, "production")
    assert length(result) == 1
    assert hd(result).id == "srv-1"
  end

  test "filter_servers returns empty list when nothing matches" do
    servers = [
      %{id: "srv-1", name: "Web Alpha", host: "10.0.0.1"}
    ]

    assert HostLive.filter_servers(servers, "zzznomatch") == []
  end

  test "fuzzy_score returns high score for exact match" do
    server = %{id: "db", name: "Database", host: "10.0.0.1"}
    assert HostLive.fuzzy_score(server, "database") == 1000
  end

  test "fuzzy_score returns 0 for no match" do
    server = %{id: "web", name: "Web Alpha", host: "10.0.0.1"}
    assert HostLive.fuzzy_score(server, "zzznomatch") == 0
  end
end
