shared_examples_for PricePoliciesController do |product_type|
  before(:each) do
    @product_type = product_type
    @authable         = Factory.create(:facility)
    @facility_account = @authable.facility_accounts.create(Factory.attributes_for(:facility_account))
    @price_group      = @authable.price_groups.create(Factory.attributes_for(:price_group))
    @price_group2     = @authable.price_groups.create(Factory.attributes_for(:price_group))
    @product          = @authable.send(product_type.to_s.pluralize).create(Factory.attributes_for(product_type, :facility_account_id => @facility_account.id))
    @price_policy     = make_price_policy
    @price_policy.should be_valid
    @params={ :facility_id => @authable.url_name, :"#{product_type}_id" => @product.url_name }
  end

  context "index" do
    before :each do
      @method=:get
      @action=:index
      @price_policy_past = make_price_policy({:start_date => 1.year.ago, :expire_date => PricePolicy.generate_expire_date(1.year.ago)})
      @price_policy_future = make_price_policy({:start_date => 1.year.from_now, :expire_date => PricePolicy.generate_expire_date(1.year.from_now)})
    end

    it_should_allow_operators_only do |user|
      assigns[:product].should == @product
      assigns[:current_price_policies].should == [@price_policy]
      assigns[:next_price_policies_by_date].keys.should include_date @price_policy_future.start_date
      response.should render_template('price_policies/index')
    end
  end

  context 'new' do
    before :each do
      @method=:get
      @action=:new
    end
    it_should_allow_managers_only {}
    context 'signed in' do
      before :each do
        maybe_grant_always_sign_in :director
      end
      it 'should assign the product' do
        do_request
        assigns[:product].should == @product
      end
      it 'should set the date to today if there are no active policies' do
        @price_policy.destroy.should be_true
        do_request
        response.code.should == "200"
        response.should be_success
        assigns[:start_date].should_not be_nil
        assigns[:start_date].should match_date Date.today
      end
      it 'should set the date to tomorrow if there are active policies' do
        do_request
        response.should be_success
        assigns[:start_date].should_not be_nil
        assigns[:start_date].should match_date(Date.today + 1.day)
      end
      it 'should set the expiration date to when the fiscal year ends' do
        do_request
        assigns[:expire_date].should == PricePolicy.generate_expire_date(Date.today)
      end
      it 'should have a new price policy for each group' do
        do_request
        assigns[:price_policies].should be_is_a Array
        price_groups = assigns[:price_policies].map(&:price_group)
        price_groups.should contain_all PriceGroup.all
      end
      it 'should set each price policy to true' do
        do_request
        (assigns[:price_policies].all?{|pp| pp.can_purchase?}).should be_true
      end
      it 'should render the new template' do
        do_request
        response.should render_template('price_policies/new')
      end
    end
  end

  context "edit" do

    before :each do
      @method=:get
      @action=:edit
      set_policy_date
      @params.merge!(:id => @price_policy.start_date.to_s)
    end

    it_should_allow_managers_only {}

    context 'signed in' do
      before :each do
        maybe_grant_always_sign_in :director
        do_request
      end
      it 'should assign start date' do
        assigns[:start_date].should == @price_policy.start_date.to_date
      end
      it 'should return the existing policies' do
        assigns[:price_policies].should be_include @price_policy
        @price_policy.should_not be_new_record
      end

      it 'should return a new policy for other groups' do
        new_price_policies = assigns[:price_policies].reject {|pp| pp.price_group == @price_group}
        new_price_policies.map(&:price_group).should contain_all(PriceGroup.all - [@price_group])
        new_price_policies.each do |pp|
          pp.should be_new_record
        end
      end
      it 'should render the edit template' do
        should render_template('price_policies/edit')
      end
    end


    it 'should not allow edit of assigned effective price policy' do
      @account  = Factory.create(:nufs_account, :account_users_attributes => [Hash[:user => @director, :created_by => @director, :user_role => 'Owner']])
      @order    = @director.orders.create(Factory.attributes_for(:order, :created_by => @director.id))
      @order_detail = @order.order_details.create(Factory.attributes_for(:order_detail).update(:product_id => @product.id, :account_id => @account.id, :price_policy => @price_policy))
      UserPriceGroupMember.create!(:price_group => @price_group, :user => @director)
      maybe_grant_always_sign_in :director
      do_request
      assigns[:start_date].should == Date.strptime(@params[:id], "%Y-%m-%d")
      assigns[:price_policies].should be_empty
      should render_template '404'
    end

  end

  context 'policy params' do

    before :each do
      @params.merge!({
        :interval => 5,
      })

      @authable.price_groups.each do |pg|
        @params.merge!(:"price_policy_#{pg.id}" => Factory.attributes_for(:"#{@product_type}_price_policy"))
      end
    end


    context "create" do

      before :each do
        @method=:post
        @action=:create
        @start_date=Time.zone.now+1.year
        @expire_date=PricePolicy.generate_expire_date(@start_date)
        @params.merge!({
          :start_date => @start_date.to_s,
          :expire_date => @expire_date.to_s
        })
      end

      it_should_allow_managers_only(:redirect) {}

      context 'signed in' do
        before :each do
          maybe_grant_always_sign_in :director
        end

        it 'should create the new price_groups' do
          do_request
          assigns[:price_policies].map(&:price_group).should contain_all PriceGroup.all
          assigns[:price_policies].each do |pp|
            pp.should_not be_new_record
          end
        end
        it 'should redirect to show on success' do
          do_request
          should redirect_to price_policy_index_path
        end

        it 'should create a new price policy for a group that has no fields, but cant purchase' do
          last_price_group = @authable.price_groups.last
          @params.delete :"price_policy_#{last_price_group.id}"
          do_request
          response.should be_redirect
          price_policies_for_empty_group = assigns[:price_policies].select {|pp| pp.price_group == last_price_group}
          price_policies_for_empty_group.size.should == 1
          price_policies_for_empty_group.first.should_not be_can_purchase
        end
        
        it 'should reject everything if expire date is before start date' do
          @params[:expire_date] = (@start_date - 2.days).to_s
          do_request
          flash[:error].should_not be_nil
          response.should render_template 'price_policies/new'
          assigns[:price_policies].each do |pp|
            pp.should be_new_record
          end
        end

        it 'should reject everything if the expiration date spans into the next fiscal year' do
          @params[:expire_date] = (PricePolicy.generate_expire_date(@start_date) + 1.day).to_s
          do_request
          response.should be
          flash[:error].should_not be_nil
          response.should render_template 'price_policies/new'
          assigns[:price_policies].each do |pp|
            pp.should be_new_record
          end
        end
      end

    end


    context "update" do

      before :each do
        @method=:put
        @action=:update
        set_policy_date
        @params.merge!(:id => @price_policy.start_date.to_s,
          :start_date => @price_policy.start_date.to_s,
          :expire_date => @price_policy.expire_date.to_s)
      end

      it_should_allow_managers_only(:redirect) {}

      context 'signed in' do
        before :each do
          maybe_grant_always_sign_in :director
        end

        it 'should redirect to show on success' do
          do_request
          should redirect_to price_policy_index_path
        end

        it 'should update the expiration dates for all price policies' do
          @new_expire_date = @price_policy.expire_date - 1.day
          @params[:expire_date] = @new_expire_date.to_s
          do_request
          @product.price_policies.for_date(@price_policy.start_date).each do |pp|
            pp.expire_date.should match_date @new_expire_date
          end
        end

        it 'should update the start_date for all price policies' do
          @new_start_date = @price_policy.start_date + 1.day
          @params[:start_date] = @new_start_date.to_s
          do_request
          assigns[:price_policies].each do |pp|
            pp.start_date.should match_date @new_start_date
          end
        end
        
        it 'should update the can_purchase for price policy' do
          last_price_group = @authable.price_groups.last
          @params[:"price_policy_#{last_price_group.id}"][:can_purchase] = false
          do_request
          @product.price_policies.for_date(@price_policy.start_date).where(:price_group_id => last_price_group.id).first.should_not be_can_purchase
        end

        it 'should create a new price policy that cant be purchased for a new price group' do
          @price_group3 = @authable.price_groups.create(Factory.attributes_for(:price_group))
          do_request
          @product.price_policies.map(&:price_group).should be_include @price_group3

          new_pp = @product.price_policies.for_date(@price_policy.start_date).where(:price_group_id => @price_group3.id).first
          new_pp.should_not be_can_purchase
        end
        it 'should reject everything if expire date is before start date' do
          @params[:expire_date] = (@price_policy.start_date - 2.days).to_s
          do_request
          flash[:error].should_not be_nil
          response.should render_template 'price_policies/edit'
          @product.price_policies.for_date(@price_policy.start_date).each do |pp|
            pp.expire_date.should match_date @price_policy.expire_date
          end
        end

        it 'should reject everything if the expiration date spans into the next fiscal year' do
          @params[:expire_date] = (PricePolicy.generate_expire_date(@price_policy.start_date) + 1.day).to_s
          do_request
          response.should be
          flash[:error].should_not be_nil
          response.should render_template 'price_policies/edit'
          @product.price_policies.for_date(@price_policy.start_date).each do |pp|
            pp.expire_date.should match_date @price_policy.expire_date
          end
        end
      end
    end


    context "destroy" do

      before :each do
        @method=:delete
        @action=:destroy
        set_policy_date(1.day)
        @params.merge!(:id => @price_policy.start_date.to_s)
        @price_policy.start_date.should > Time.zone.now
      end

      it_should_allow_managers_only(:redirect) {}

      context 'signed in' do
        before :each do
          maybe_grant_always_sign_in :director
        end
        it 'should destroy the price policies' do
          do_request
          assigns[:price_policies].each do |pp|
            pp.should be_destroyed
          end
        end
        it 'should redirect to the price policies page for the product' do
          do_request
          should redirect_to price_policy_index_path
        end
        it 'should not allow destroying an active price policy' do
          @price_policy.update_attributes(:start_date => Time.zone.now - 1.day, :expire_date => Time.zone.now + 1.day)
          @params.merge!(:id => @price_policy.start_date.to_s)
          do_request
          flash[:error].should_not be_nil
          response.should redirect_to price_policy_index_path
        end
        
        it 'should raise a 404 if there are no price policies for that date' do
          @params.merge!(:id => (@price_policy.start_date + 1.day).to_s)
          do_request
          response.code.should == "404"
        end
      end
    end

  end

  private

  def price_policy_index_path
    "/facilities/#{@authable.url_name}/#{@product_type.to_s.pluralize}/#{@product.url_name}/price_policies"
  end

  def make_price_policy(extra_attr = {})
    extra_attr.merge!(:price_group_id => @price_group.id)
    @product.send(:"#{@product_type}_price_policies").create(Factory.attributes_for(:"#{@product_type}_price_policy", extra_attr))
  end

  def set_policy_date(time_in_future=0)
    @price_policy.start_date=Time.zone.now.beginning_of_day + time_in_future
    @price_policy.expire_date=PricePolicy.generate_expire_date(@price_policy)
    assert @price_policy.save
  end

end