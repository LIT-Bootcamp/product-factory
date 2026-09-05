# frozen_string_literal: true

module ProductFactory
  module GitHub
    module Queries
      SNAPSHOT = <<~GRAPHQL
        query($organization:String!, $repository:String!, $cursor:String) {
          viewer { login }
          organization(login:$organization) {
            id
            projectsV2(first:100, after:$cursor) {
              nodes {
                id number title shortDescription public closed
                items { totalCount }
                repositories(first:100) { nodes { nameWithOwner } }
              }
              pageInfo { hasNextPage endCursor }
            }
          }
          repository(owner:$organization, name:$repository) { id name nameWithOwner }
        }
      GRAPHQL

      VIEWS = <<~GRAPHQL
        query($organization:String!, $number:Int!) {
          organization(login:$organization) {
            projectV2(number:$number) {
              views(first:100) {
                nodes {
                  id number name layout filter configuration {
                    visibleFields(first:100) {
                      nodes {
                        ... on ProjectV2Field { name }
                        ... on ProjectV2IterationField { name }
                        ... on ProjectV2MultiSelectField { name }
                        ... on ProjectV2SingleSelectField { name }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL
    end
  end
end
