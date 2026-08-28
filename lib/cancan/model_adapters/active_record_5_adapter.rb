# frozen_string_literal: true

module CanCan
  module ModelAdapters
    class ActiveRecord5Adapter < ActiveRecord4Adapter
      AbstractAdapter.inherited(self)

      def self.for_class?(model_class)
        version_greater_or_equal?('5.0.0') && model_class <= ActiveRecord::Base
      end

      # rails 5 is capable of using strings in enum
      # but often people use symbols in rules
      def self.matches_condition?(subject, name, value)
        return super if Array.wrap(value).all? { |x| x.is_a? Integer }

        attribute = subject.send(name)
        raw_attribute = subject.class.send(name.to_s.pluralize)[attribute]
        !(Array(value).map(&:to_s) & [attribute, raw_attribute]).empty?
      end

      private

      def build_joins_relation(relation, *where_conditions)
        strategy_class.new(adapter: self, relation: relation, where_conditions: where_conditions).execute!
      end

      def strategy_class
        strategy_class_name = CanCan.accessible_by_strategy.to_s.camelize
        CanCan::ModelAdapters::Strategies.const_get(strategy_class_name)
      end

      def sanitize_sql(conditions)
        if conditions.is_a?(Hash)
          sanitize_sql_activerecord5(conditions)
        else
          @model_class.send(:sanitize_sql, conditions)
        end
      end

      def sanitize_sql_activerecord5(conditions)
        table = @model_class.send(:arel_table)
        table_metadata = ActiveRecord::TableMetadata.new(@model_class, table)
        predicate_builder = ActiveRecord::PredicateBuilder.new(table_metadata)

        nodes = predicate_builder.build_from_hash(conditions.stringify_keys)
        nodes.one? ? nodes.first : Arel::Nodes::And.new(nodes)
      end

      def false_sql
        Arel.sql('1=0')
      end

      def true_sql
        Arel.sql('1=1')
      end

      def merge_non_empty_conditions(behavior, conditions_hash, sql)
        conditions = sanitize_sql(conditions_hash)
        conditions = Arel.sql(conditions) if conditions.is_a?(::String)
        sql = Arel.sql(sql) if sql.is_a?(::String)
        case sql
        when true_sql
          behavior ? true_sql : Arel::Nodes::Not.new(Arel::Nodes::Grouping.new(conditions))
        when false_sql
          behavior ? conditions : false_sql
        else
          grouped_conditions = Arel::Nodes::Grouping.new(conditions)
          grouped_sql = Arel::Nodes::Grouping.new(sql)
          if behavior
            Arel::Nodes::Grouping.new(arel_or(grouped_conditions, grouped_sql))
          else
            Arel::Nodes::Grouping.new(Arel::Nodes::And.new([Arel::Nodes::Not.new(grouped_conditions), grouped_sql]))
          end
        end
      end

      def arel_or(left, right)
        if self.class.version_greater_or_equal?('8.0.0')
          Arel::Nodes::Or.new([left, right])
        else
          Arel::Nodes::Or.new(left, right)
        end
      end
    end
  end
end
