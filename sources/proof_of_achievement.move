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

    struct ModuleData has store {
        token_data_id: TokenDataId,
        minting_enabled: bool,
        users: Table<address, bool>
    }

    struct ModuleDataCollection has store, key {
        signer_cap: SignerCapability,
        data: vector<ModuleData>
    }

    const ENOT_AUTHORIZED: u64 = 1;
    const ECOLLECTION_EXPIRED: u64 = 2;
    const EMINTING_DISABLED: u64 = 3;
    const ENOT_ELIGIBLE: u64 = 4;
    const EALREADY_MINTED: u64 = 5;
    const NONE_EXISTENT: u64 = 6;

    fun init_module(resource_signer: &signer) {
        let resource_signer_cap = resource_account::retrieve_resource_account_cap(resource_signer, @sender);
        move_to(resource_signer, ModuleDataCollection{
            signer_cap: resource_signer_cap,
            data: vector::empty<ModuleData>()
        })
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

    public entry fun add_user_to_set(caller: &signer, user: address, collection_index: u64) acquires ModuleDataCollection {
        let caller_addr = signer::address_of(caller);

        assert!(caller_addr == @admin_addr, error::permission_denied(ENOT_AUTHORIZED));

        let module_data_collection = borrow_global_mut<ModuleDataCollection>(@edenx);

        assert!(collection_index < vector::length(&module_data_collection.data),  error::permission_denied(ENOT_AUTHORIZED));

        let module_data = vector::borrow_mut(&mut module_data_collection.data, collection_index);

        assert!(!table::contains(&module_data.users, user), error::permission_denied(NONE_EXISTENT));

        table::add(&mut module_data.users, user, true);
    }

    public entry fun mint_event_ticket(receiver: &signer, collection_index: u64) acquires ModuleDataCollection {
        let module_data_collection = borrow_global_mut<ModuleDataCollection>(@edenx);
        let receiver_address = signer::address_of(receiver);

        assert!(collection_index < vector::length(&module_data_collection.data), error::permission_denied(ENOT_AUTHORIZED));
        let module_data = vector::borrow_mut(&mut module_data_collection.data, collection_index);

        assert!(table::contains(&module_data.users, receiver_address), error::permission_denied(NONE_EXISTENT));

        assert!(module_data.minting_enabled, error::permission_denied(EMINTING_DISABLED));
        assert!(is_user_eligible(module_data, receiver_address), error::permission_denied(ENOT_ELIGIBLE));

        let resource_signer = account::create_signer_with_capability(&module_data_collection.signer_cap);
        let token_id = token::mint_token(&resource_signer, module_data.token_data_id, 1);
        token::direct_transfer(&resource_signer, receiver, token_id, 1);
    }

    fun update_user_mint_status(module_data: &mut ModuleData, user: address) {
        assert!(!table::contains(&module_data.users, user), error::permission_denied(NONE_EXISTENT));

        table::upsert(&mut module_data.users, user, false)
    }

    fun is_user_eligible(module_data: &ModuleData, user: address): bool {
        let users_minting_status = table::borrow(&module_data.users, user);

        return *users_minting_status
    }

    public entry fun set_minting_enabled(caller: &signer, collection_index: u64, minting_enabled: bool) acquires ModuleDataCollection {
        let module_data_collection = borrow_global_mut<ModuleDataCollection>(@edenx);
        let caller_address = signer::address_of(caller);

        assert!(caller_address == @admin_addr, error::permission_denied(ENOT_AUTHORIZED));
        assert!(collection_index < vector::length(&module_data_collection.data), error::permission_denied(ENOT_AUTHORIZED));

        let module_data = vector::borrow_mut(&mut module_data_collection.data, collection_index);
        module_data.minting_enabled = minting_enabled;
    }

    #[view]
    public fun get_all_module_data(): vector<token::TokenDataId> acquires ModuleDataCollection {
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
