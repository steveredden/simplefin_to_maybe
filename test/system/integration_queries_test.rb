require "application_system_test_case"

class IntegrationQueriesTest < ApplicationSystemTestCase
  setup do
    @integration_query = integration_queries(:one)
  end

  test "visiting the index" do
    visit integration_queries_url
    assert_selector "h1", text: "Integration queries"
  end

  test "should create integration query" do
    visit integration_queries_url
    click_on "New integration query"

    fill_in "Account", with: @integration_query.account_id
    fill_in "Integration", with: @integration_query.integration_id
    fill_in "Last executed at", with: @integration_query.last_executed_at
    fill_in "Name", with: @integration_query.name
    fill_in "Query params", with: @integration_query.query_params
    fill_in "Response data", with: @integration_query.response_data
    click_on "Create Integration query"

    assert_text "Integration query was successfully created"
    click_on "Back"
  end

  test "should update Integration query" do
    visit integration_query_url(@integration_query)
    click_on "Edit this integration query", match: :first

    fill_in "Account", with: @integration_query.account_id
    fill_in "Integration", with: @integration_query.integration_id
    fill_in "Last executed at", with: @integration_query.last_executed_at
    fill_in "Name", with: @integration_query.name
    fill_in "Query params", with: @integration_query.query_params
    fill_in "Response data", with: @integration_query.response_data
    click_on "Update Integration query"

    assert_text "Integration query was successfully updated"
    click_on "Back"
  end

  test "should destroy Integration query" do
    visit integration_query_url(@integration_query)
    accept_confirm { click_on "Destroy this integration query", match: :first }

    assert_text "Integration query was successfully destroyed"
  end
end
