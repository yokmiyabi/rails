require 'test_helper'

class ItemsControllerTest < ActionController::TestCase
  test "should get recent" do
    get :recent
    assert_response :success
  end

end
