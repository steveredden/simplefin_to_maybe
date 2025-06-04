class IntegrationQueriesController < ApplicationController
  before_action :set_integration_query, only: %i[ show edit update destroy ]

  # GET /integration_queries or /integration_queries.json
  def index
    @integration_queries = IntegrationQuery.all
  end

  # GET /integration_queries/1 or /integration_queries/1.json
  def show
  end

  # GET /integration_queries/new
  def new
    @integration_query = IntegrationQuery.new
  end

  # GET /integration_queries/1/edit
  def edit
  end

  # POST /integration_queries or /integration_queries.json
  def create
    @integration_query = IntegrationQuery.new(integration_query_params)

    respond_to do |format|
      if @integration_query.save
        format.html { redirect_to @integration_query, notice: "Integration query was successfully created." }
        format.json { render :show, status: :created, location: @integration_query }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @integration_query.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /integration_queries/1 or /integration_queries/1.json
  def update
    respond_to do |format|
      if @integration_query.update(integration_query_params)
        format.html { redirect_to @integration_query, notice: "Integration query was successfully updated." }
        format.json { render :show, status: :ok, location: @integration_query }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @integration_query.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /integration_queries/1 or /integration_queries/1.json
  def destroy
    @integration_query.destroy!

    respond_to do |format|
      format.html { redirect_to integration_queries_path, status: :see_other, notice: "Integration query was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_integration_query
      @integration_query = IntegrationQuery.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def integration_query_params
      params.require(:integration_query).permit(:account_id, :integration_id, :name, :query_params, :response_data, :last_executed_at)
    end
end
