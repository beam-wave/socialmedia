defmodule SocialmediaWeb.ChannelSettingsTest do
  use SocialmediaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Socialmedia.Fixtures

  test "every channel template is offered, including ones starting with _", %{conn: conn} do
    ch = channel()
    {:ok, view, _} = live(conn, ~p"/channels/#{ch.id}/settings")

    assert has_element?(view, "option[value='_motivation2live__']")
    assert has_element?(view, "option[value='puree_heartz']")
    refute has_element?(view, "option[value='_shared']")
  end

  test "a pasted token is trimmed; both token kinds are accepted" do
    ch = channel()
    alias Socialmedia.Channels

    assert {:ok, ch} = Channels.update_channel(ch, %{access_token: " IGAAxyz \n"})
    assert ch.access_token == "IGAAxyz"

    assert {:ok, %{access_token: "EAAabc"}} =
             Channels.update_channel(ch, %{access_token: "EAAabc"})
  end

  test "each token kind talks to its own API host" do
    alias Socialmedia.Instagram.Graph
    assert Graph.base_url("EAAabc") =~ "graph.facebook.com"
    assert Graph.base_url("IGAAabc") =~ "graph.instagram.com"
    refute Graph.refreshable?("EAAabc")
    assert Graph.refreshable?("IGAAabc")
  end

  test "toggling dry run with the token field empty keeps the saved token", %{conn: conn} do
    {:ok, ch} = Socialmedia.Channels.update_channel(channel(), %{access_token: "IGAAsaved"})
    {:ok, view, _} = live(conn, ~p"/channels/#{ch.id}/settings")

    view |> form("form", channel: %{dry_run: "false", access_token: ""}) |> render_change()
    view |> form("form", channel: %{dry_run: "false", access_token: ""}) |> render_submit()

    ch = Socialmedia.Channels.get_channel!(ch.id)
    assert ch.dry_run == false and ch.access_token == "IGAAsaved"
  end
end
