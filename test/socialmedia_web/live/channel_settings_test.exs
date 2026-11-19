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

  test "a Facebook token is refused with a hint; an Instagram one is trimmed and kept" do
    ch = channel()
    alias Socialmedia.Channels

    assert {:error, cs} = Channels.update_channel(ch, %{access_token: "EAAabc123"})
    assert [{msg, _}] = cs.errors |> Keyword.get_values(:access_token)
    assert msg =~ "Facebook token"

    assert {:ok, ch} = Channels.update_channel(ch, %{access_token: " IGAAxyz \n"})
    assert ch.access_token == "IGAAxyz"
  end
end
