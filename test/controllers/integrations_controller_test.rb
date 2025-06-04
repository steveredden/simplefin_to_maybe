require "test_helper"

class IntegrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @integration = integrations(:one)
  end

  test "should get index" do
    get integrations_url
    assert_response :success
  end

  test "should get new" do
    get new_integration_url
    assert_response :success
  end

  test "should create integration" do
    assert_difference("Integration.count") do
      post integrations_url, params: { integration: { credentials: @integration.credentials, description: @integration.description, name: @integration.name } }
    end

    assert_redirected_to integration_url(Integration.last)
  end

  test "should show integration" do
    get integration_url(@integration)
    assert_response :success
  end

  test "should get edit" do
    get edit_integration_url(@integration)
    assert_response :success
  end

  test "should update integration" do
    patch integration_url(@integration), params: { integration: { credentials: @integration.credentials, description: @integration.description, name: @integration.name } }
    assert_redirected_to integration_url(@integration)
  end

  test "should destroy integration" do
    assert_difference("Integration.count", -1) do
      delete integration_url(@integration)
    end

    assert_redirected_to integrations_url
  end
end
