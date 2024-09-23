module edenx::proof_of_achievement {
    use std::error;
    use std::string;
    use aptos_framework::account::SignerCapability;
    use aptos_token::token::TokenDataId;
    use aptos_token::token;
    use std::signer;
    use std::string::String;
    use std::vector;
    use aptos_std::table;
    use aptos_std::table::Table;
    use aptos_framework::account;
    use aptos_framework::resource_account;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_account;
    use aptos_framework::randomness;
    use aptos_framework::event;

    const ENOT_AUTHORIZED: u64 = 1000;
    const ECOLLECTION_EXPIRED: u64 = 2000;
    const EMINTING_DISABLED: u64 = 3000;
    const ENOT_ELIGIBLE: u64 = 4000;
    const EALREADY_MINTED: u64 = 5000;
    const NONE_EXISTENT: u64 = 6000;
    const ONE_DAY_IN_SECONDS: u64 = 86400;
    const EALREADY_SIGNED_IN: u64 = 8000;

    const STATUS_NOT_ELIGIBLE: u64 = 0;
    const STATUS_ELIGIBLE: u64 = 1;
    const STATUS_ALREADY_MINTED: u64 = 2;

    const NOT_YET_AVAILABLE: u64 = 9000;

    struct ModuleData has store {
        token_data_id: TokenDataId,
        minting_enabled: bool,
        users: Table<address, bool>
    }

    struct ModuleDataCollection has store, key {
        signer_cap: SignerCapability,
        data: vector<ModuleData>
    }

    struct SignInData has store {
        sign_in_count: u64,
        last_sign_in_time: u64,
    }

    struct SignInModule has key {
        sign_in_data: Table<address, SignInData>,
    }

    struct LearnToEarnUser has key {
        laean_to_earn_user_data: Table<address, u64>
    }

    struct LearnToEarnStauts has store, key {
        learn_to_earn_status: bool,
        laean_to_earn_user_status: Table<address, u64>
    }

    #[event]
    struct RewardEventHandle has drop, store {
        receiver: address,
        amount: u64,
    }

    fun init_module(resource_signer: &signer) {
        let resource_signer_cap = resource_account::retrieve_resource_account_cap(resource_signer, @sender);
        move_to(resource_signer, ModuleDataCollection{
            signer_cap: resource_signer_cap,
            data: vector::empty<ModuleData>()
        });

        let sign_in_data = table::new();
        move_to(resource_signer, SignInModule { sign_in_data });

        move_to(resource_signer, LearnToEarnUser {
            laean_to_earn_user_data: table::new()
        });

        move_to(resource_signer, LearnToEarnStauts {
            learn_to_earn_status: false,
            laean_to_earn_user_status: table::new()
        });

    }

    public entry fun create_OAT(
        _caller: &signer,
        _collection_name: String,
        _description: String,
        _collection_uri: String,
        _token_name: String,
        _token_uri: String
    ) acquires ModuleDataCollection {
        let caller_address = signer::address_of(_caller);
        assert!(caller_address == @admin_addr, error::permission_denied(ENOT_AUTHORIZED));
        let module_data_collection = borrow_global_mut<ModuleDataCollection>(@edenx);

        let maximum_supply = 0;
        let mutate_setting = vector<bool>[false, false, false];

        let resource_signer = account::create_signer_with_capability(&module_data_collection.signer_cap);
        token::create_collection(
            &resource_signer,
            _collection_name,
            _description,
            _collection_uri,
            maximum_supply,
            mutate_setting
        );

        let token_data_id = token::create_tokendata(
            &resource_signer,
            _collection_name,
            _token_name,
            string::utf8(b""),
            0,
            _token_uri,
            signer::address_of(_caller),
            1,
            0,
            token::create_token_mutability_config(&vector<bool>[ false, false, false, false, true ]),
            vector<string::String>[string::utf8(b"given_to")],
            vector<vector<u8>>[b""],
            vector<string::String>[ string::utf8(b"address") ],
        );


        let module_data = ModuleData {
            token_data_id,
            minting_enabled: true,
            users: table::new()
        };

        vector::push_back(&mut module_data_collection.data, module_data);

    }

    public entry fun add_user_to_set(caller: &signer, user: address, collection_index: u64)
    acquires ModuleDataCollection {
        let caller_addr = signer::address_of(caller);

        assert!(caller_addr == @admin_addr, error::permission_denied(ENOT_AUTHORIZED));

        let module_data_collection = borrow_global_mut<ModuleDataCollection>(@edenx);

        assert!(collection_index < vector::length(&module_data_collection.data),  error::permission_denied(ENOT_AUTHORIZED));

        let module_data = vector::borrow_mut(&mut module_data_collection.data, collection_index);

        assert!(!table::contains(&module_data.users, user), error::permission_denied(NONE_EXISTENT));

        table::add(&mut module_data.users, user, true);
    }

    public entry fun mint_event_ticket(receiver: &signer, collection_index: u64)
    acquires ModuleDataCollection {
        let module_data_collection = borrow_global_mut<ModuleDataCollection>(@edenx);
        let receiver_address = signer::address_of(receiver);

        assert!(collection_index < vector::length(&module_data_collection.data), error::permission_denied(ENOT_AUTHORIZED));
        let module_data = vector::borrow_mut(&mut module_data_collection.data, collection_index);

        //Temporary feature, cancel verification.
        if (table::contains(&module_data.users, receiver_address)) {
            assert!(module_data.minting_enabled, error::permission_denied(EMINTING_DISABLED));
            assert!(is_user_eligible(module_data, receiver_address), error::permission_denied(ENOT_ELIGIBLE));
        } else {
            table::add(&mut module_data.users, receiver_address, true);
        };

        // assert!(table::contains(&module_data.users, receiver_address), error::permission_denied(NONE_EXISTENT));
        // assert!(module_data.minting_enabled, error::permission_denied(EMINTING_DISABLED));
        // assert!(is_user_eligible(module_data, receiver_address), error::permission_denied(ENOT_ELIGIBLE));

        let resource_signer = account::create_signer_with_capability(&module_data_collection.signer_cap);
        let token_id = token::mint_token(&resource_signer, module_data.token_data_id, 1);
        token::direct_transfer(&resource_signer, receiver, token_id, 1);
        update_user_mint_status(module_data, receiver_address)
    }

    fun update_user_mint_status(module_data: &mut ModuleData, user: address) {
        assert!(table::contains(&module_data.users, user), error::permission_denied(NONE_EXISTENT));

        table::upsert(&mut module_data.users, user, false)
    }

    fun is_user_eligible(module_data: &ModuleData, user: address): bool {
        let users_minting_status = table::borrow(&module_data.users, user);

        return *users_minting_status
    }

    public entry fun set_minting_enabled(caller: &signer, collection_index: u64, minting_enabled: bool)
    acquires ModuleDataCollection {
        let module_data_collection = borrow_global_mut<ModuleDataCollection>(@edenx);
        let caller_address = signer::address_of(caller);

        assert!(caller_address == @admin_addr, error::permission_denied(ENOT_AUTHORIZED));
        assert!(collection_index < vector::length(&module_data_collection.data), error::permission_denied(ENOT_AUTHORIZED));

        let module_data = vector::borrow_mut(&mut module_data_collection.data, collection_index);
        module_data.minting_enabled = minting_enabled;
    }

    public entry fun sign_in(caller: &signer)
    acquires SignInModule {
        let sign_in_module = borrow_global_mut<SignInModule>(@edenx);
        let current_time = timestamp::now_seconds();

        let address = signer::address_of(caller);

        if (table::contains(&sign_in_module.sign_in_data, address)) {
            let sign_in_data = table::borrow_mut(&mut sign_in_module.sign_in_data, address);
            assert!(
                (current_time - sign_in_data.last_sign_in_time) >= ONE_DAY_IN_SECONDS,
                error::permission_denied(EALREADY_SIGNED_IN)
            );

            sign_in_data.sign_in_count = sign_in_data.sign_in_count + 1;
            sign_in_data.last_sign_in_time = current_time;
        } else {
            let new_sign_in_data = SignInData {
                sign_in_count: 1,
                last_sign_in_time: current_time,
            };
            table::add(&mut sign_in_module.sign_in_data, address, new_sign_in_data);
        }
    }

    public entry fun set_learn_to_earn_status(caller: &signer, status: bool)
    acquires LearnToEarnStauts {
        let caller_addr = signer::address_of(caller);
        assert!(caller_addr == @admin_addr, error::permission_denied(ENOT_AUTHORIZED));

        let learn_to_earn_status_result = borrow_global_mut<LearnToEarnStauts>(@edenx);

        learn_to_earn_status_result.learn_to_earn_status = status
    }

    public entry fun set_learn_to_earn_user_status(caller: &signer, receive: address, earn_id: u64)
    acquires LearnToEarnStauts {
        let caller_addr = signer::address_of(caller);
        assert!(caller_addr == @admin_addr, error::permission_denied(ENOT_AUTHORIZED));

        let learn_to_earn_status_result = borrow_global_mut<LearnToEarnStauts>(@edenx);
        assert!(learn_to_earn_status_result.learn_to_earn_status, NOT_YET_AVAILABLE);

        table::upsert(&mut learn_to_earn_status_result.laean_to_earn_user_status, receive, earn_id);

    }

    fun send_random_reward(): u64 {
        let random_amount = randomness::u64_range(1, 10);
        let reward = random_amount * 1000000;

        return reward
    }

    #[randomness]
    public(friend) entry fun earn(caller: &signer, earn_id: u64)
    acquires ModuleDataCollection, LearnToEarnUser, LearnToEarnStauts {

        let receive = signer::address_of(caller);

        let learn_to_earn_status_result = borrow_global_mut<LearnToEarnStauts>(@edenx);
        assert!(learn_to_earn_status_result.learn_to_earn_status, NOT_YET_AVAILABLE);

        assert!(table::contains(&learn_to_earn_status_result.laean_to_earn_user_status, receive), ENOT_AUTHORIZED);

        let user_earn_id = table::borrow(&learn_to_earn_status_result.laean_to_earn_user_status, receive);

        assert!((*user_earn_id as u64) == earn_id, ENOT_AUTHORIZED);

        let amount = send_random_reward();

        let module_data_collection = borrow_global_mut<ModuleDataCollection>(@edenx);
        let resource_signer = account::create_signer_with_capability(&module_data_collection.signer_cap);

        aptos_account::transfer(&resource_signer, receive, amount);

        table::remove(&mut learn_to_earn_status_result.laean_to_earn_user_status, receive);

        event::emit<RewardEventHandle>(
            RewardEventHandle {
                receiver: receive,
                amount: amount,
            },
        );

        let learn_to_earn_user_data = borrow_global_mut<LearnToEarnUser>(@edenx);

        if (table::contains(&learn_to_earn_user_data.laean_to_earn_user_data, receive)) {
            let current_amount_ref = table::borrow_mut(&mut learn_to_earn_user_data.laean_to_earn_user_data, receive);
            *current_amount_ref = *current_amount_ref + amount;
        } else {
            table::add(&mut learn_to_earn_user_data.laean_to_earn_user_data, receive, amount);
        }


    }

    #[view]
    public fun get_user_earn_id(account: address): u64
    acquires LearnToEarnStauts {
        let learn_to_earn_status_result = borrow_global<LearnToEarnStauts>(@edenx);

        if (table::contains(&learn_to_earn_status_result.laean_to_earn_user_status, account)) {
            return *table::borrow(&learn_to_earn_status_result.laean_to_earn_user_status, account)
        };

        return 0
    }

    #[view]
    public fun get_sign_in_count(account: address): u64
    acquires SignInModule {
        let sign_in_module = borrow_global<SignInModule>(@edenx);
        if (table::contains(&sign_in_module.sign_in_data, account)) {
            let sign_in_data = table::borrow(&sign_in_module.sign_in_data, account);
            sign_in_data.sign_in_count
        } else {
            0
        }
    }

    #[view]
    public fun get_user_mini_OAT_status(account: address, collection_index: u64): u64
    acquires ModuleDataCollection {
        let module_data_collection = borrow_global_mut<ModuleDataCollection>(@edenx);

        if (collection_index > vector::length(&module_data_collection.data)) {
            return STATUS_NOT_ELIGIBLE
        };

        let module_data = vector::borrow_mut(&mut module_data_collection.data, collection_index);

        if (!table::contains(&module_data.users, account)) {
            return STATUS_NOT_ELIGIBLE
        };

        let users_minting_status = table::borrow(&module_data.users, account);

        if (!*users_minting_status) {
            return STATUS_ELIGIBLE
        };

        return STATUS_ALREADY_MINTED
    }

    #[view]
    public fun get_all_module_data(): vector<token::TokenDataId>
    acquires ModuleDataCollection {
        let module_data_collection = borrow_global<ModuleDataCollection>(@edenx);

        let token_data_ids = vector::empty<token::TokenDataId>();

        let len = vector::length(&module_data_collection.data);

        let i = 0;

        while (i < len) {
            let module_data = vector::borrow(&module_data_collection.data, i);
            vector::push_back(&mut token_data_ids, module_data.token_data_id);
            i = i + 1;
        };

        return  token_data_ids
    }
}
