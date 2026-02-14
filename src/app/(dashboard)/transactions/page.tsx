import { createServerSupabaseClient } from '@/lib/supabase/server'
import { TransactionList } from '@/components/transactions/TransactionList'
import { AddTransactionDialog } from '@/components/transactions/AddTransactionDialog'

export default async function TransactionsPage() {
  const supabase = await createServerSupabaseClient()
  
  const { data: { user } } = await supabase.auth.getUser()
  
  const { data: memberships } = await supabase
    .from('organization_memberships')
    .select('organization_id')
    .eq('user_id', user!.id)
    .eq('status', 'active')
    .limit(1)
    .single()

  const { data: transactions } = await supabase
    .from('transactions')
    .select(`
      *,
      category:categories(name, color)
    `)
    .eq('organization_id', memberships?.organization_id)
    .order('transaction_date', { ascending: false })

  const { data: categories } = await supabase
    .from('categories')
    .select('*')
    .or(`organization_id.eq.${memberships?.organization_id},is_system_default.eq.true`)

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-3xl font-bold">Transaktioner</h1>
        <AddTransactionDialog 
          organizationId={memberships?.organization_id!} 
          categories={categories || []} 
        />
      </div>

      <TransactionList 
        transactions={transactions || []} 
        organizationId={memberships?.organization_id!}
      />
    </div>
  )
}