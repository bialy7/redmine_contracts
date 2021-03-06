require File.dirname(__FILE__) + '/../test_helper'

class DeliverableTest < ActiveSupport::TestCase
  should_belong_to :contract
  should_belong_to :manager
  should_have_many :labor_budgets
  should_have_many :overhead_budgets
  should_have_many :fixed_budgets
  should_have_many :issues

  should_validate_presence_of :title
  should_validate_presence_of :type
  should_validate_presence_of :manager

  should_allow_values_for :status, "", nil, 'open', 'locked', 'closed'
  should_not_allow_values_for :status, "other", "things", "1"

  should "default status to open" do
    assert_equal "open", Deliverable.new.status
  end

  context "#total=" do
    should "strip dollar signs when writing" do
      d = Deliverable.new
      d.total = '$100.00'
      
      assert_equal 100.00, d.total.to_f
    end

    should "strip commas when writing" do
      d = Deliverable.new
      d.total = '20,100.00'
      
      assert_equal 20100.00, d.total.to_f
    end

    should "strip spaces when writing" do
      d = Deliverable.new
      d.total = '20 100.00'
      
      assert_equal 20100.00, d.total.to_f
    end
  end

  context "with a locked contract" do
    should "block creating a new deliverable" do
      contract = Contract.generate!(:status => "locked")
      deliverable = FixedDeliverable.spawn(:contract => contract)

      assert !deliverable.valid?
      assert deliverable.errors.on_base.include?("Can't create a deliverable on a locked contract")
    end

    should "block deleting a deliverable" do
      contract = Contract.generate!
      deliverable = FixedDeliverable.generate!(:contract => contract).reload
      assert contract.lock!

      assert_no_difference("Deliverable.count") do
        deliverable.destroy
      end
      
    end
  end

  context "with a closed contract" do
    should "block creating a new deliverable" do
      contract = Contract.generate!(:status => "closed")
      deliverable = FixedDeliverable.spawn(:contract => contract)

      assert !deliverable.valid?
      assert deliverable.errors.on_base.include?("Can't create a deliverable on a closed contract")
    end

    should "block deleting a deliverable" do
      contract = Contract.generate!
      deliverable = FixedDeliverable.generate!(:contract => contract).reload
      assert contract.close!

      assert_no_difference("Deliverable.count") do
        deliverable.destroy
      end
      
    end
  end

  context "#billable_time_entry_activities" do
    setup do
      configure_overhead_plugin
      create_contract_and_deliverable
    end
    
    should "include all billable activities" do
      @billable_activity2 = TimeEntryActivity.generate!.reload
      @billable_activity2.custom_field_values = { @custom_field.id => 'true' }
      assert @billable_activity2.save

      assert @deliverable.billable_time_entry_activities.include?(@billable_activity), "Activity not included"
      assert @deliverable.billable_time_entry_activities.include?(@billable_activity2), "Activity not included"
      
    end
    
    should "not include nonbillable activities" do
      assert !@deliverable.billable_time_entry_activities.include?(@non_billable_activity), "Non billable Activity included"
    end
    
  end

  context "#non_billable_time_entry_activities" do
    setup do
      configure_overhead_plugin
      create_contract_and_deliverable
    end
    
    should "include all billable activities" do
      @non_billable_activity2 = TimeEntryActivity.generate!.reload
      @non_billable_activity2.custom_field_values = { @custom_field.id => 'false' }
      assert @non_billable_activity2.save

      assert @deliverable.non_billable_time_entry_activities.include?(@non_billable_activity), "Activity not included"
      assert @deliverable.non_billable_time_entry_activities.include?(@non_billable_activity2), "Activity not included"
      
    end
    
    should "not include billable activities" do
      assert !@deliverable.non_billable_time_entry_activities.include?(@billable_activity), "Billable Activity included"
    end
    
  end

  context "#spent_for_activity" do
    should "return the total amount spent for an activity" do
      configure_overhead_plugin
      create_contract_and_deliverable
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager,
                                               :hours => 5,
                                               :amount => 100
                                             })

      assert_equal 500.0, @deliverable.spent_for_activity(@billable_activity).to_f
    end
  end

  context "#budget_for_activity" do
    should "return the total amount budgeted for an activity" do
      configure_overhead_plugin
      create_contract_and_deliverable
      @deliverable.labor_budgets << LaborBudget.spawn(:budget => 100, :hours => 10, :time_entry_activity => @billable_activity)
      @deliverable.labor_budgets << LaborBudget.spawn(:budget => 100, :hours => 10, :time_entry_activity => @billable_activity)
      @deliverable.save!

      assert_equal 600.0, @deliverable.budget_for_activity(@billable_activity).to_f # 200 * 3 months (retainer)
    end
    
  end
  
  context "#hours_spent_for_activity" do
    should "return the total hours spent for an activity" do
      configure_overhead_plugin
      create_contract_and_deliverable
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager,
                                               :hours => 5,
                                               :amount => 100
                                             })

      assert_equal 5.0, @deliverable.hours_spent_for_activity(@billable_activity).to_f

    end
    
  end

  context "#hours_budget_for_activity" do
    should "return the total hours budgeted for an activity" do
      configure_overhead_plugin
      create_contract_and_deliverable
      @deliverable.labor_budgets << LaborBudget.spawn(:budget => 100, :hours => 10, :time_entry_activity => @billable_activity)
      @deliverable.labor_budgets << LaborBudget.spawn(:budget => 100, :hours => 10, :time_entry_activity => @billable_activity)
      @deliverable.save!

      assert_equal 60.0, @deliverable.hours_budget_for_activity(@billable_activity).to_f # 20 * 3 months (retainer)
    end
    
  end

  context "#users_with_billable_time" do
    setup do
      configure_overhead_plugin
      create_contract_and_deliverable
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager
                                             })
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @non_billable_activity,
                                               :user => @manager
                                             })
      @non_billable_user = User.generate!
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @non_billable_activity,
                                               :user => @non_billable_user
                                             })

    end
    
    should "include users with billable Time Entries" do
      assert @deliverable.users_with_billable_time.include?(@manager), "Manager not included"
    end
    
    should "not include users with only nonbillable Time Entries" do
      assert !@deliverable.users_with_billable_time.include?(@non_billable_user), "Non billable user included"
    end
  end
  
  context "#users_with_non_billable_time" do
    setup do
      configure_overhead_plugin
      create_contract_and_deliverable
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager
                                             })
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @non_billable_activity,
                                               :user => @manager
                                             })
      @billable_user = User.generate!
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @billable_user
                                             })

    end
    
    should "include users with billable Time Entries" do
      assert @deliverable.users_with_non_billable_time.include?(@manager), "Manager not included"
    end
    
    should "not include users with only nonbillable Time Entries" do
      assert !@deliverable.users_with_non_billable_time.include?(@billable_user), "Billable user included"
    end
  end

  context "#hours_spent_for_user" do
    setup do
      configure_overhead_plugin
      create_contract_and_deliverable
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager,
                                               :hours => 5
                                             })
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager,
                                               :hours => 5
                                             })
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @non_billable_activity,
                                               :user => @manager,
                                               :hours => 5
                                             })

    end
    
    context "with billable_time_only as true" do
      should "return the total number of hours the user has logged on billable time entries" do
        assert_equal 10, @deliverable.hours_spent_for_user(@manager, true)
      end
    end
    
    context "with billable_time_only as false" do
      should "return the total number of hours the user has logged on non-billable time entries" do
        assert_equal 5, @deliverable.hours_spent_for_user(@manager, false)
      end
    end

  end

  context "#spent_for_user" do
    setup do
      configure_overhead_plugin
      create_contract_and_deliverable
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager,
                                               :hours => 5,
                                               :amount => 100
                                             })
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager,
                                               :hours => 5,
                                               :amount => 100
                                             })
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @non_billable_activity,
                                               :user => @manager,
                                               :hours => 5,
                                               :amount => 100
                                             })

    end
    
    context "with billable_time_only as true" do
      should "return the total cost the user has logged on billable time entries" do
        assert_equal 1000, @deliverable.spent_for_user(@manager, true)
      end
    end
    
    context "with billable_time_only as false" do
      should "return the total cost the user has logged on non-billable time entries" do
        assert_equal 500, @deliverable.spent_for_user(@manager, false)
      end
    end

  end

  context "#issue_categories_with_billable_time" do
    setup do
      configure_overhead_plugin
      create_contract_and_deliverable
      @category_one = IssueCategory.generate!(:project => @project)
      @category_two = IssueCategory.generate!(:project => @project)

      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager,
                                               :issue_category => @category_one
                                             })
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @non_billable_activity,
                                               :user => @manager,
                                               :issue_category => @category_one
                                             })
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @non_billable_activity,
                                               :user => @manager,
                                               :issue_category => @category_two
                                             })

    end
    
    should "include categories with billable Time Entries" do
      assert @deliverable.issue_categories_with_billable_time.include?(@category_one)
    end
    
    should "not include categories with only nonbillable Time Entries" do
      assert !@deliverable.issue_categories_with_billable_time.include?(@category_two)
    end
  end
  
  context "#issue_categories_with_non_billable_time" do
    setup do
      configure_overhead_plugin
      create_contract_and_deliverable
      @category_one = IssueCategory.generate!(:project => @project)
      @category_two = IssueCategory.generate!(:project => @project)

      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @non_billable_activity,
                                               :user => @manager,
                                               :issue_category => @category_one
                                             })
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager,
                                               :issue_category => @category_one
                                             })
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager,
                                               :issue_category => @category_two
                                             })

    end
    
    should "include categories with non-billable Time Entries" do
      assert @deliverable.issue_categories_with_non_billable_time.include?(@category_one)
    end
    
    should "not include categories with only billable Time Entries" do
      assert !@deliverable.issue_categories_with_non_billable_time.include?(@category_two)
    end
  end

  context "#spent_for_issue_category" do
    setup do
      configure_overhead_plugin
      create_contract_and_deliverable
      @category_one = IssueCategory.generate!(:project => @project)

      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager,
                                               :hours => 5,
                                               :amount => 100,
                                               :issue_category => @category_one
                                             })
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager,
                                               :hours => 5,
                                               :amount => 100,
                                               :issue_category => @category_one
                                             })
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @non_billable_activity,
                                               :user => @manager,
                                               :hours => 5,
                                               :amount => 100,
                                               :issue_category => @category_one
                                             })

    end
    
    context "with billable_time_only as true" do
      should "return the total cost the category has logged on billable time entries" do
        assert_equal 1000, @deliverable.spent_for_issue_category(@category_one, true)
      end
    end
    
    context "with billable_time_only as false" do
      should "return the total cost the category has logged on non-billable time entries" do
        assert_equal 500, @deliverable.spent_for_issue_category(@category_one, false)
      end
    end

  end

  context "#hours_spent_for_issue_category" do
    setup do
      configure_overhead_plugin
      create_contract_and_deliverable
      @category_one = IssueCategory.generate!(:project => @project)

      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager,
                                               :hours => 5,
                                               :amount => 100,
                                               :issue_category => @category_one
                                             })
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @billable_activity,
                                               :user => @manager,
                                               :hours => 5,
                                               :amount => 100,
                                               :issue_category => @category_one
                                             })
      create_issue_with_time_for_deliverable(@deliverable, {
                                               :activity => @non_billable_activity,
                                               :user => @manager,
                                               :hours => 5,
                                               :amount => 100,
                                               :issue_category => @category_one
                                             })

    end
    
    context "with billable_time_only as true" do
      should "return the total hours the category has logged on billable time entries" do
        assert_equal 10, @deliverable.hours_spent_for_issue_category(@category_one, true)
      end
    end
    
    context "with billable_time_only as false" do
      should "return the total hours the category has logged on non-billable time entries" do
        assert_equal 5, @deliverable.hours_spent_for_issue_category(@category_one, false)
      end
    end

  end
end
