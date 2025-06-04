require "test_helper"

class IntegrationQueriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @integration_query = integration_queries(:one)
  end

  test "should get index" do
    get integration_queries_url
    assert_response :success
  end

  test "should get new" do
    get new_integration_query_url
    assert_response :success
  end

  test "should create integration_query" do
    assert_difference("IntegrationQuery.count") do
      post integration_queries_url, params: { integration_query: { account_id: @integration_query.account_id, integration_id: @integration_query.integration_id, last_executed_at: @integration_query.last_executed_at, name: @integration_query.name, query_params: @integration_query.query_params, response_data: @integration_query.response_data } }
    end

    assert_redirected_to integration_query_url(IntegrationQuery.last)
  end

  test "should show integration_query" do
    get integration_query_url(@integration_query)
    assert_response :success
  end

  test "should get edit" do
    get edit_integration_query_url(@integration_query)
    assert_response :success
  end

  test "should update integration_query" do
    patch integration_query_url(@integration_query), params: { integration_query: { account_id: @integration_query.account_id, integration_id: @integration_query.integration_id, last_executed_at: @integration_query.last_executed_at, name: @integration_query.name, query_params: @integration_query.query_params, response_data: @integration_query.response_data } }
    assert_redirected_to integration_query_url(@integration_query)
  end

  test "should destroy integration_query" do
    assert_difference("IntegrationQuery.count", -1) do
      delete integration_query_url(@integration_query)
    end

    assert_redirected_to integration_queries_url
  end
end
