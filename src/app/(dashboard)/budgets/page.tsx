import { createServerSupabaseClient } from '@/lib/supabase/server'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

export default async function BudgetsPage() {
  const supabase = await createServerSupabaseClient()
  
  const { data: { user } } = await supabase.auth.getUser()
  
  const { data: memberships } = await supabase
    .from('organization_memberships')
    .select('organization_id')
    .eq('user_id', user!.id)
    .eq('status', 'active')
    .limit(1)
    .single()

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">Budgetar</h1>
      
      <Card>
        <CardHeader>
          <CardTitle>Budgetfunktion</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-gray-600">
            Budgetfunktionen kommer snart! För nu, använd Transaktioner för att spåra dina utgifter.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}