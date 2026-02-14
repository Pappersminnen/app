import { createServerSupabaseClient } from '@/lib/supabase/server'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import Link from 'next/link'
import { Button } from '@/components/ui/button'

export default async function DashboardPage() {
  const supabase = await createServerSupabaseClient()
  
  const { data: { user } } = await supabase.auth.getUser()
  
  const { data: memberships } = await supabase
    .from('organization_memberships')
    .select(`
      *,
      organization:organizations(*)
    `)
    .eq('user_id', user!.id)
    .eq('status', 'active')

  const currentOrg = memberships?.[0]?.organization

  const { data: transactions } = await supabase
    .from('transactions')
    .select('*')
    .eq('organization_id', currentOrg?.id)
    .order('transaction_date', { ascending: false })
    .limit(5)

  const now = new Date()
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1)
  
  const { data: monthTransactions } = await supabase
    .from('transactions')
    .select('amount, type')
    .eq('organization_id', currentOrg?.id)
    .gte('transaction_date', startOfMonth.toISOString().split('T')[0])

  const monthlySpending = monthTransactions
    ?.filter(t => t.type === 'expense')
    .reduce((sum, t) => sum + Number(t.amount), 0) || 0

  const monthlyIncome = monthTransactions
    ?.filter(t => t.type === 'income')
    .reduce((sum, t) => sum + Number(t.amount), 0) || 0

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-3xl font-bold text-gray-900">Översikt</h1>
        <Link href="/transactions">
          <Button>Ny Transaktion</Button>
        </Link>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-gray-600">
              Utgifter denna månad
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {monthlySpending.toLocaleString('sv-SE')} kr
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-gray-600">
              Inkomster denna månad
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-green-600">
              +{monthlyIncome.toLocaleString('sv-SE')} kr
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-gray-600">
              Netto
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className={`text-2xl font-bold ${monthlyIncome - monthlySpending >= 0 ? 'text-green-600' : 'text-red-600'}`}>
              {(monthlyIncome - monthlySpending).toLocaleString('sv-SE')} kr
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Senaste Transaktioner</CardTitle>
        </CardHeader>
        <CardContent>
          {transactions && transactions.length > 0 ? (
            <div className="space-y-3">
              {transactions.map((transaction) => (
                <div key={transaction.id} className="flex justify-between items-center border-b pb-3 last:border-b-0">
                  <div>
                    <p className="font-medium">{transaction.description}</p>
                    <p className="text-sm text-gray-500">
                      {new Date(transaction.transaction_date).toLocaleDateString('sv-SE')}
                    </p>
                  </div>
                  <div className={`font-semibold ${transaction.type === 'expense' ? 'text-red-600' : 'text-green-600'}`}>
                    {transaction.type === 'expense' ? '-' : '+'}{Number(transaction.amount).toLocaleString('sv-SE')} kr
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-gray-500 text-center py-8">Inga transaktioner än</p>
          )}
        </CardContent>
      </Card>
    </div>
  )
}