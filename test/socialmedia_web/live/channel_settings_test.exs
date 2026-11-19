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
end
