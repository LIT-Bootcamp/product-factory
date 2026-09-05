# frozen_string_literal: true

module ProductFactory
  module GitHub
    module Mutations
      CREATE_PROJECT = <<~GRAPHQL
        mutation($input:CreateProjectV2Input!) { createProjectV2(input:$input) { projectV2 { id } } }
      GRAPHQL
      UPDATE_PROJECT = <<~GRAPHQL
        mutation($input:UpdateProjectV2Input!) { updateProjectV2(input:$input) { projectV2 { id } } }
      GRAPHQL
      LINK_PROJECT = <<~GRAPHQL
        mutation($input:LinkProjectV2ToRepositoryInput!) { linkProjectV2ToRepository(input:$input) { repository { id } } }
      GRAPHQL
      UPDATE_FIELD = <<~GRAPHQL
        mutation($input:UpdateProjectV2FieldInput!) { updateProjectV2Field(input:$input) { projectV2Field { id } } }
      GRAPHQL
      UPDATE_VIEW = <<~GRAPHQL
        mutation($input:UpdateProjectV2ViewInput!) { updateProjectV2View(input:$input) { projectV2View { id } } }
      GRAPHQL
    end
  end
end
