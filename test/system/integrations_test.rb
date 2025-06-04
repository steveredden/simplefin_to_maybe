require "application_system_test_case"

class IntegrationsTest < ApplicationSystemTestCase
  setup do
    @integration = integrations(:one)
  end

  test "visiting the index" do
    visit integrations_url
    assert_selector "h1", text: "Integrations"
  end

  test "should create integration" do
    visit integrations_url
    click_on "New integration"

    fill_in "Credentials", with: @integration.credentials
    fill_in "Description", with: @integration.description
    fill_in "Name", with: @integration.name
    click_on "Create Integration"

    assert_text "Integration was successfully created"
    click_on "Back"
  end

  test "should update Integration" do
    visit integration_url(@integration)
    click_on "Edit this integration", match: :first

    fill_in "Credentials", with: @integration.credentials
    fill_in "Description", with: @integration.description
    fill_in "Name", with: @integration.name
    click_on "Update Integration"

    assert_text "Integration was successfully updated"
    click_on "Back"
  end

  test "should destroy Integration" do
    visit integration_url(@integration)
    accept_confirm { click_on "Destroy this integration", match: :first }

    assert_text "Integration was successfully destroyed"
  end
end
